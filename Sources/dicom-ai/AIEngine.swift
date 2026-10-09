// NEMA-verified: 2026a, checked 2026-10-01 — carries no DICOM-standard data beyond reading the Image Pixel Module (Rows, Columns, Bits Allocated, Samples per Pixel, Photometric Interpretation, Pixel Data) of PS3.3 2026a Tables C.7-11a, C.7-11b and C.7-11c with MONOCHROME2 (a C.7.6.3.1.2 Defined Term) as fallback; CoreML inference plumbing
import Foundation
import DICOMKit
import DICOMCore

#if canImport(CoreML)
import CoreML
#endif

#if canImport(Vision)
import Vision
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreImage)
import CoreImage
#endif

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Preprocessing Options

/// Options for image preprocessing
struct PreprocessingOptions: Sendable {
    /// Normalization strategy
    enum NormalizationStrategy: Sendable {
        case none
        case minMax(min: Double, max: Double)
        case zScore(mean: Double, std: Double)
        case imageNet  // Standard ImageNet normalization
    }
    
    /// Target image size for resizing
    var targetSize: (width: Int, height: Int)?
    
    /// Normalization strategy to apply
    var normalization: NormalizationStrategy = .none
    
    /// Whether to apply padding to maintain aspect ratio
    var maintainAspectRatio: Bool = false
    
    /// Padding value (used when maintainAspectRatio is true)
    var paddingValue: Double = 0.0
    
    static let `default` = PreprocessingOptions()
    
    static let imageNetNormalized = PreprocessingOptions(
        normalization: .imageNet
    )
}

// MARK: - AI Engine

@available(macOS 14.0, iOS 17.0, *)
class AIEngine {
    #if canImport(CoreML)
    private let model: MLModel?
    #else
    private let model: Any?
    #endif
    private let verbose: Bool
    private let modelURL: URL
    private let preprocessingOptions: PreprocessingOptions

    /// The model's version string from its CoreML metadata, when it has one: the default
    /// Algorithm Version (111003, DCM) of PS3.16 TID 4019 row 2 in the SR dicom-ai writes
    var modelVersion: String? {
        #if canImport(CoreML)
        let version = model?.modelDescription.metadata[.versionString] as? String
        let trimmed = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
        #else
        return nil
        #endif
    }
    
    init(modelURL: URL, verbose: Bool = false, preprocessingOptions: PreprocessingOptions = .default) throws {
        self.modelURL = modelURL
        self.verbose = verbose
        self.preprocessingOptions = preprocessingOptions
        
        #if canImport(CoreML)
        // Try to load the CoreML model
        do {
            let compiledURL: URL
            if modelURL.pathExtension == "mlmodelc" {
                // Already compiled
                compiledURL = modelURL
            } else if modelURL.pathExtension == "mlmodel" {
                // Need to compile
                if verbose {
                    print("Compiling CoreML model...")
                }
                compiledURL = try MLModel.compileModel(at: modelURL)
            } else {
                throw AIError.invalidModelFormat("Model must be .mlmodel or .mlmodelc")
            }
            
            let configuration = MLModelConfiguration()
            #if os(macOS) || os(iOS)
            configuration.computeUnits = .all  // Use CPU, GPU, and Neural Engine
            #endif
            
            self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
            
            if verbose {
                print("Model loaded successfully")
                if let modelDescription = self.model?.modelDescription {
                    print("Input: \(modelDescription.inputDescriptionsByName.keys)")
                    print("Output: \(modelDescription.outputDescriptionsByName.keys)")
                }
            }
        } catch {
            if verbose {
                print("Failed to load CoreML model: \(error)")
            }
            self.model = nil
            throw AIError.modelLoadFailed("Failed to load CoreML model: \(error.localizedDescription)")
        }
        #else
        self.model = nil
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
    
    // MARK: - Image Preprocessing
    
    func preprocessImage(from dataSet: DataSet, frameIndex: Int = 0) throws -> ProcessedImage {
        // Extract pixel data from DICOM
        guard let pixelData = dataSet[.pixelData]?.valueData else {
            throw AIError.noPixelData("No pixel data found in DICOM file")
        }
        
        // Get image dimensions
        guard let rows = dataSet.uint16(for: .rows),
              let columns = dataSet.uint16(for: .columns) else {
            throw AIError.missingMetadata("Missing Rows or Columns in DICOM")
        }
        
        let bitsAllocated = dataSet.uint16(for: .bitsAllocated) ?? 16
        let samplesPerPixel = dataSet.uint16(for: .samplesPerPixel) ?? 1
        let photometricInterpretation = dataSet.string(for: .photometricInterpretation) ?? "MONOCHROME2"
        
        if verbose {
            print("Image dimensions: \(columns)x\(rows), \(bitsAllocated) bits, \(samplesPerPixel) samples per pixel")
            print("Photometric interpretation: \(photometricInterpretation)")
        }
        
        // Create initial processed image structure
        var processedImage = ProcessedImage(
            width: Int(columns),
            height: Int(rows),
            bitsPerPixel: Int(bitsAllocated),
            samplesPerPixel: Int(samplesPerPixel),
            photometricInterpretation: photometricInterpretation,
            pixelData: pixelData
        )
        
        // Apply preprocessing options
        processedImage = try applyPreprocessing(to: processedImage, options: preprocessingOptions)
        
        return processedImage
    }
    
    /// Apply preprocessing transformations to image
    private func applyPreprocessing(to image: ProcessedImage, options: PreprocessingOptions) throws -> ProcessedImage {
        var result = image
        
        // Apply resizing if requested
        if let targetSize = options.targetSize {
            result = try resize(image: result, to: targetSize, maintainAspectRatio: options.maintainAspectRatio, paddingValue: options.paddingValue)
        }
        
        // Apply normalization
        result = try normalize(image: result, strategy: options.normalization)
        
        return result
    }
    
    /// Resize image to target size
    private func resize(image: ProcessedImage, to targetSize: (width: Int, height: Int), maintainAspectRatio: Bool, paddingValue: Double) throws -> ProcessedImage {
        if !maintainAspectRatio && image.width == targetSize.width && image.height == targetSize.height {
            return image
        }
        
        if verbose {
            print("Resizing image from \(image.width)x\(image.height) to \(targetSize.width)x\(targetSize.height)")
        }
        
        // For now, return the original image with updated dimensions metadata
        // Real implementation would need pixel interpolation
        var resizedPixelData = image.pixelData
        var newWidth = targetSize.width
        var newHeight = targetSize.height
        
        if maintainAspectRatio {
            // Calculate aspect ratio preserving dimensions
            let aspectRatio = Double(image.width) / Double(image.height)
            let targetAspectRatio = Double(targetSize.width) / Double(targetSize.height)
            
            if aspectRatio > targetAspectRatio {
                // Width-constrained
                newWidth = targetSize.width
                newHeight = Int(Double(targetSize.width) / aspectRatio)
            } else {
                // Height-constrained
                newHeight = targetSize.height
                newWidth = Int(Double(targetSize.height) * aspectRatio)
            }
            
            // Add padding if needed
            if newWidth < targetSize.width || newHeight < targetSize.height {
                // Create padded image (simplified - would need proper implementation)
                let paddedSize = targetSize.width * targetSize.height * (image.bitsPerPixel / 8)
                resizedPixelData = Data(repeating: UInt8(paddingValue), count: paddedSize)
            }
        }
        
        return ProcessedImage(
            width: newWidth,
            height: newHeight,
            bitsPerPixel: image.bitsPerPixel,
            samplesPerPixel: image.samplesPerPixel,
            photometricInterpretation: image.photometricInterpretation,
            pixelData: resizedPixelData
        )
    }
    
    /// Normalize image pixel values
    private func normalize(image: ProcessedImage, strategy: PreprocessingOptions.NormalizationStrategy) throws -> ProcessedImage {
        guard case .none = strategy else {
            if verbose {
                print("Applying normalization: \(strategy)")
            }
            // Normalization would modify pixel data here
            // For now, return original image
            return image
        }
        return image
    }
    
    // MARK: - Classification
    
    func classify(image: ProcessedImage, topK: Int = 5, threshold: Double = 0.0) throws -> [Prediction] {
        #if canImport(CoreML)
        guard let model = model else {
            throw AIError.modelNotLoaded("Model not loaded")
        }
        
        // Convert processed image to MLFeatureProvider
        let input = try createMLInput(from: image)
        
        // Run prediction
        let output = try model.prediction(from: input)
        
        // Extract classification results
        let predictions = try extractClassificationPredictions(from: output, topK: topK, threshold: threshold)
        
        return predictions
        #else
        throw AIError.platformNotSupported("CoreML not available")
        #endif
    }
    
    // MARK: - Segmentation
    
    func segment(image: ProcessedImage) throws -> SegmentationMask {
        #if canImport(CoreML)
        guard let model = model else {
            throw AIError.modelNotLoaded("Model not loaded")
        }
        
        // Convert processed image to MLFeatureProvider
        let input = try createMLInput(from: image)
        
        // Run prediction
        let output = try model.prediction(from: input)
        
        // Extract segmentation mask
        let mask = try extractSegmentationMask(from: output, width: image.width, height: image.height)
        
        return mask
        #else
        throw AIError.platformNotSupported("CoreML not available")
        #endif
    }
    
    // MARK: - Detection
    
    func detect(image: ProcessedImage, confidenceThreshold: Double, iouThreshold: Double, maxDetections: Int) throws -> [Detection] {
        #if canImport(CoreML)
        guard let model = model else {
            throw AIError.modelNotLoaded("Model not loaded")
        }
        
        // Convert processed image to MLFeatureProvider
        let input = try createMLInput(from: image)
        
        // Run prediction
        let output = try model.prediction(from: input)
        
        // Extract detection results
        var detections = try extractDetections(from: output, confidenceThreshold: confidenceThreshold)
        
        // Apply non-maximum suppression
        detections = applyNMS(detections: detections, iouThreshold: iouThreshold)
        
        // Limit to max detections
        if detections.count > maxDetections {
            detections = Array(detections.prefix(maxDetections))
        }
        
        return detections
        #else
        throw AIError.platformNotSupported("CoreML not available")
        #endif
    }
    
    // MARK: - Enhancement
    
    func enhance(image: ProcessedImage) throws -> ProcessedImage {
        #if canImport(CoreML)
        guard let model = model else {
            throw AIError.modelNotLoaded("Model not loaded")
        }
        
        // Convert processed image to MLFeatureProvider
        let input = try createMLInput(from: image)
        
        // Run prediction
        let output = try model.prediction(from: input)
        
        // Extract enhanced image
        let enhancedImage = try extractEnhancedImage(from: output, sourceImage: image)
        
        return enhancedImage
        #else
        throw AIError.platformNotSupported("CoreML not available")
        #endif
    }
    
    // MARK: - Helper Methods
    
    #if canImport(CoreML)
    private func createMLInput(from image: ProcessedImage) throws -> MLFeatureProvider {
        // This is a simplified implementation
        // Real implementation would need to handle different model input types
        
        guard let model = model else {
            throw AIError.modelNotLoaded("Model not loaded")
        }
        
        let inputDescriptions = model.modelDescription.inputDescriptionsByName
        guard let firstInput = inputDescriptions.first else {
            throw AIError.invalidModelFormat("No input found in model")
        }
        
        let inputName = firstInput.key
        let inputDescription = firstInput.value
        
        // For now, we'll create a simple dictionary-based feature provider
        // Real implementation would convert image data to appropriate format
        let features: [String: Any] = [inputName: image.pixelData as Any]
        
        return try MLDictionaryFeatureProvider(dictionary: features)
    }
    
    private func extractClassificationPredictions(from output: MLFeatureProvider, topK: Int, threshold: Double) throws -> [Prediction] {
        // Try to find classification probabilities in output
        let outputDescriptions = model?.modelDescription.outputDescriptionsByName ?? [:]
        
        var predictions: [Prediction] = []
        
        // Look for common output names
        for (name, description) in outputDescriptions {
            if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                // Convert MultiArray to predictions
                predictions = try extractPredictionsFromMultiArray(multiArray, threshold: threshold)
                break
            } else if let dictionary = output.featureValue(for: name)?.dictionaryValue {
                // Handle dictionary output (label: probability)
                for (label, prob) in dictionary {
                    if let labelStr = label as? String, let probDouble = prob as? Double {
                        if probDouble >= threshold {
                            predictions.append(Prediction(label: labelStr, confidence: probDouble))
                        }
                    }
                }
                break
            }
        }
        
        // Sort by confidence and take top K
        predictions.sort { $0.confidence > $1.confidence }
        return Array(predictions.prefix(topK))
    }
    
    private func extractPredictionsFromMultiArray(_ multiArray: MLMultiArray, threshold: Double) throws -> [Prediction] {
        var predictions: [Prediction] = []
        
        // Assuming the multiArray contains class probabilities
        let count = multiArray.count
        for i in 0..<count {
            let confidence = multiArray[i].doubleValue
            if confidence >= threshold {
                predictions.append(Prediction(label: "class_\(i)", confidence: confidence))
            }
        }
        
        return predictions
    }
    
    private func extractSegmentationMask(from output: MLFeatureProvider, width: Int, height: Int) throws -> SegmentationMask {
        // Try to find segmentation mask in output
        let outputDescriptions = model?.modelDescription.outputDescriptionsByName ?? [:]
        
        for (name, _) in outputDescriptions {
            if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                // Assume multiArray contains segmentation mask
                let maskData = try convertMultiArrayToMask(multiArray)
                return SegmentationMask(width: width, height: height, data: maskData, numClasses: 2)
            }
        }
        
        throw AIError.invalidModelOutput("Could not extract segmentation mask from model output")
    }
    
    private func convertMultiArrayToMask(_ multiArray: MLMultiArray) throws -> Data {
        // Convert MLMultiArray to Data
        let count = multiArray.count
        var data = Data(count: count)
        
        for i in 0..<count {
            let value = multiArray[i].uint8Value
            data[i] = value
        }
        
        return data
    }
    
    private func extractDetections(from output: MLFeatureProvider, confidenceThreshold: Double) throws -> [Detection] {
        // This is a simplified implementation
        // Real detection models would have specific output formats (e.g., YOLO, SSD)
        
        var detections: [Detection] = []
        
        // Try to extract bounding boxes and confidence scores
        // This would need to be customized based on the model architecture
        
        return detections
    }
    
    private func extractEnhancedImage(from output: MLFeatureProvider, sourceImage: ProcessedImage) throws -> ProcessedImage {
        // Extract enhanced image from model output
        let outputDescriptions = model?.modelDescription.outputDescriptionsByName ?? [:]
        
        for (name, _) in outputDescriptions {
            if let multiArray = output.featureValue(for: name)?.multiArrayValue {
                // Convert multiArray to pixel data
                let enhancedPixelData = try convertMultiArrayToPixelData(multiArray)
                
                return ProcessedImage(
                    width: sourceImage.width,
                    height: sourceImage.height,
                    bitsPerPixel: sourceImage.bitsPerPixel,
                    samplesPerPixel: sourceImage.samplesPerPixel,
                    photometricInterpretation: sourceImage.photometricInterpretation,
                    pixelData: enhancedPixelData
                )
            }
        }
        
        throw AIError.invalidModelOutput("Could not extract enhanced image from model output")
    }
    
    private func convertMultiArrayToPixelData(_ multiArray: MLMultiArray) throws -> Data {
        // Convert MLMultiArray to pixel data
        let count = multiArray.count
        var data = Data(count: count * 2) // Assuming 16-bit pixels
        
        for i in 0..<count {
            let value = multiArray[i].uint16Value
            data.withUnsafeMutableBytes { ptr in
                ptr.storeBytes(of: value.littleEndian, toByteOffset: i * 2, as: UInt16.self)
            }
        }
        
        return data
    }
    
    private func applyNMS(detections: [Detection], iouThreshold: Double) -> [Detection] {
        // Non-Maximum Suppression implementation
        var result: [Detection] = []
        var remaining = detections.sorted { $0.confidence > $1.confidence }
        
        while !remaining.isEmpty {
            let best = remaining.removeFirst()
            result.append(best)
            
            remaining = remaining.filter { detection in
                let iou = calculateIoU(best.bbox, detection.bbox)
                return iou < iouThreshold
            }
        }
        
        return result
    }
    
    private func calculateIoU(_ box1: BoundingBox, _ box2: BoundingBox) -> Double {
        let x1 = max(box1.x, box2.x)
        let y1 = max(box1.y, box2.y)
        let x2 = min(box1.x + box1.width, box2.x + box2.width)
        let y2 = min(box1.y + box1.height, box2.y + box2.height)
        
        let intersectionWidth = max(0, x2 - x1)
        let intersectionHeight = max(0, y2 - y1)
        let intersectionArea = intersectionWidth * intersectionHeight
        
        let box1Area = box1.width * box1.height
        let box2Area = box2.width * box2.height
        let unionArea = box1Area + box2Area - intersectionArea
        
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
    #endif
}

// MARK: - Data Structures

struct ProcessedImage: Sendable {
    let width: Int
    let height: Int
    let bitsPerPixel: Int
    let samplesPerPixel: Int
    let photometricInterpretation: String
    let pixelData: Data
}

struct Prediction: Sendable {
    let label: String
    let confidence: Double
}

struct SegmentationMask: Sendable {
    let width: Int
    let height: Int
    let data: Data
    let numClasses: Int
}

struct Detection: Sendable {
    let label: String
    let confidence: Double
    let bbox: BoundingBox
}

struct BoundingBox: Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Errors

enum AIError: Error, LocalizedError, Sendable {
    case platformNotSupported(String)
    case modelLoadFailed(String)
    case modelNotLoaded(String)
    case invalidModelFormat(String)
    case invalidModelOutput(String)
    case noPixelData(String)
    case missingMetadata(String)
    case missingOutput(String)
    case invalidLabelsFile(String)
    case notImplemented(String)
    
    var errorDescription: String? {
        switch self {
        case .platformNotSupported(let message),
             .modelLoadFailed(let message),
             .modelNotLoaded(let message),
             .invalidModelFormat(let message),
             .invalidModelOutput(let message),
             .noPixelData(let message),
             .missingMetadata(let message),
             .missingOutput(let message),
             .invalidLabelsFile(let message),
             .notImplemented(let message):
            return message
        }
    }
}

// MARK: - Ensemble Inference

@available(macOS 14.0, iOS 17.0, *)
class EnsembleEngine {
    private let engines: [AIEngine]
    private let strategy: EnsembleStrategy
    private let verbose: Bool
    
    enum EnsembleStrategy: Sendable {
        case average
        case voting
        case weighted([Double])
        case max
    }
    
    init(modelURLs: [URL], strategy: EnsembleStrategy = .average, verbose: Bool = false, preprocessingOptions: PreprocessingOptions = .default) throws {
        guard !modelURLs.isEmpty else {
            throw AIError.invalidModelFormat("At least one model required for ensemble")
        }
        
        self.strategy = strategy
        self.verbose = verbose
        
        // Load all models
        var loadedEngines: [AIEngine] = []
        for url in modelURLs {
            do {
                let engine = try AIEngine(modelURL: url, verbose: verbose, preprocessingOptions: preprocessingOptions)
                loadedEngines.append(engine)
            } catch {
                if verbose {
                    print("Failed to load model \(url.lastPathComponent): \(error)")
                }
                throw error
            }
        }
        
        self.engines = loadedEngines
        
        if verbose {
            print("Loaded \(engines.count) models for ensemble inference")
        }
    }
    
    /// Perform ensemble classification
    func classify(image: ProcessedImage, topK: Int = 5, threshold: Double = 0.0) throws -> [Prediction] {
        // Get predictions from all models
        var allPredictions: [[Prediction]] = []
        for engine in engines {
            let predictions = try engine.classify(image: image, topK: topK, threshold: threshold)
            allPredictions.append(predictions)
        }
        
        // Combine predictions based on strategy
        let ensemblePredictions = combineClassificationPredictions(allPredictions, strategy: strategy)
        
        // Sort by confidence and return top K
        let sorted = ensemblePredictions.sorted { $0.confidence > $1.confidence }
        return Array(sorted.prefix(topK))
    }
    
    /// Perform ensemble detection
    func detect(image: ProcessedImage, confidenceThreshold: Double, iouThreshold: Double, maxDetections: Int) throws -> [Detection] {
        // Get detections from all models
        var allDetections: [[Detection]] = []
        for engine in engines {
            let detections = try engine.detect(
                image: image,
                confidenceThreshold: confidenceThreshold,
                iouThreshold: iouThreshold,
                maxDetections: maxDetections
            )
            allDetections.append(detections)
        }
        
        // Combine detections (simple concatenation + NMS for now)
        let combined = allDetections.flatMap { $0 }
        
        // Apply NMS to ensemble results
        #if canImport(CoreML)
        let nmsDetections = applyNMSToDetections(combined, iouThreshold: iouThreshold)
        return Array(nmsDetections.prefix(maxDetections))
        #else
        return Array(combined.prefix(maxDetections))
        #endif
    }
    
    // MARK: - Helper Methods
    
    private func combineClassificationPredictions(_ predictions: [[Prediction]], strategy: EnsembleStrategy) -> [Prediction] {
        guard !predictions.isEmpty else { return [] }
        
        // Collect all unique labels
        var labelScores: [String: [Double]] = [:]
        for modelPredictions in predictions {
            for prediction in modelPredictions {
                labelScores[prediction.label, default: []].append(prediction.confidence)
            }
        }
        
        // Combine scores based on strategy
        var result: [Prediction] = []
        for (label, scores) in labelScores {
            let combinedScore: Double
            switch strategy {
            case .average:
                combinedScore = scores.reduce(0, +) / Double(scores.count)
            case .voting:
                // Count how many models predicted this class
                combinedScore = Double(scores.count) / Double(engines.count)
            case .weighted(let weights):
                // Apply weights (must match number of models)
                if weights.count == engines.count {
                    combinedScore = zip(scores, weights).map(*).reduce(0, +) / weights.reduce(0, +)
                } else {
                    combinedScore = scores.reduce(0, +) / Double(scores.count)
                }
            case .max:
                combinedScore = scores.max() ?? 0.0
            }
            result.append(Prediction(label: label, confidence: combinedScore))
        }
        
        return result
    }
    
    #if canImport(CoreML)
    private func applyNMSToDetections(_ detections: [Detection], iouThreshold: Double) -> [Detection] {
        var result: [Detection] = []
        var remaining = detections.sorted { $0.confidence > $1.confidence }
        
        while !remaining.isEmpty {
            let best = remaining.removeFirst()
            result.append(best)
            
            remaining = remaining.filter { detection in
                let iou = calculateIoU(best.bbox, detection.bbox)
                return iou < iouThreshold
            }
        }
        
        return result
    }
    
    private func calculateIoU(_ box1: BoundingBox, _ box2: BoundingBox) -> Double {
        let x1 = max(box1.x, box2.x)
        let y1 = max(box1.y, box2.y)
        let x2 = min(box1.x + box1.width, box2.x + box2.width)
        let y2 = min(box1.y + box1.height, box2.y + box2.height)
        
        let intersectionWidth = max(0, x2 - x1)
        let intersectionHeight = max(0, y2 - y1)
        let intersectionArea = intersectionWidth * intersectionHeight
        
        let box1Area = box1.width * box1.height
        let box2Area = box2.width * box2.height
        let unionArea = box1Area + box2Area - intersectionArea
        
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
    #endif
}

// MARK: - Batch Processor

@available(macOS 14.0, iOS 17.0, *)
class BatchProcessor {
    private let engine: AIEngine
    private let verbose: Bool
    
    init(engine: AIEngine, verbose: Bool = false) {
        self.engine = engine
        self.verbose = verbose
    }
    
    /// Process multiple files in batch
    func processBatch(
        files: [URL],
        operation: BatchOperation,
        confidenceThreshold: Double = 0.5,
        topK: Int = 5
    ) async throws -> [BatchResult] {
        var results: [BatchResult] = []
        
        for (index, fileURL) in files.enumerated() {
            if verbose {
                print("Processing \(index + 1)/\(files.count): \(fileURL.lastPathComponent)")
            }
            
            do {
                let fileData = try Data(contentsOf: fileURL)
                let dicomFile = try DICOMFile.read(from: fileData, force: true)
                let dataSet = dicomFile.dataSet
                
                let processedImage = try engine.preprocessImage(from: dataSet)
                
                let result: BatchResult
                switch operation {
                case .classify:
                    let predictions = try engine.classify(image: processedImage, topK: topK, threshold: confidenceThreshold)
                    result = BatchResult(
                        filePath: fileURL.path,
                        success: true,
                        predictions: predictions,
                        error: nil
                    )
                case .segment:
                    let mask = try engine.segment(image: processedImage)
                    result = BatchResult(
                        filePath: fileURL.path,
                        success: true,
                        segmentationMask: mask,
                        error: nil
                    )
                case .detect:
                    let detections = try engine.detect(
                        image: processedImage,
                        confidenceThreshold: confidenceThreshold,
                        iouThreshold: 0.5,
                        maxDetections: 10
                    )
                    result = BatchResult(
                        filePath: fileURL.path,
                        success: true,
                        detections: detections,
                        error: nil
                    )
                }
                
                results.append(result)
            } catch {
                if verbose {
                    print("Error processing \(fileURL.lastPathComponent): \(error)")
                }
                results.append(BatchResult(
                    filePath: fileURL.path,
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }
        
        return results
    }
    
    enum BatchOperation: Sendable {
        case classify
        case segment
        case detect
    }
}

// MARK: - Batch Result

struct BatchResult: Sendable {
    let filePath: String
    let success: Bool
    var predictions: [Prediction]?
    var segmentationMask: SegmentationMask?
    var detections: [Detection]?
    var error: String?
}
