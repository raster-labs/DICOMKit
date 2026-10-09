// NEMA-verified: 2026a, checked 2026-10-01 — Segment subcommand: --segment-category / --segment-type values are checked against PS3.16 2026a CID 7150 / CID 7151 keyword tables (SegmentPropertyCodes.swift); --algorithm-version is Algorithm Version (111003, DCM), PS3.16 2026a TID 4019 row 2 (M), Algorithm Name (111001, DCM) / Segment Algorithm Name (0062,0009, PS3.3 Table C.8.20-4) is the model file name; dicom-sr / dicom-seg / enhance outputs written as PS3.10 files; the 46 options are otherwise plumbing
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

#if canImport(CoreML)
import CoreML
#endif

#if canImport(Vision)
import Vision
#endif

struct DICOMAI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-ai",
        abstract: "AI/ML integration for DICOM image analysis and enhancement",
        discussion: """
            Integrate AI/ML models for DICOM image analysis, enhancement, and automated reporting.
            Supports CoreML models on Apple platforms and ONNX models via CoreML conversion.
            
            Examples:
              dicom-ai classify chest-xray.dcm --model pneumonia.mlmodel
              dicom-ai segment abdomen-ct.dcm --model organs.mlmodel --output seg.dcm
              dicom-ai detect brain-mri.dcm --model lesion.mlmodel --confidence 0.7
              dicom-ai enhance noisy-image.dcm --model denoise.mlmodel
              dicom-ai batch series/*.dcm --model classifier.mlmodel --output results.json
            """,
        version: "1.4.0",
        subcommands: [
            Classify.self,
            Segment.self,
            Detect.self,
            Enhance.self,
            Batch.self,
            Registry.self,
        ]
    )
}

// MARK: - Common Options

struct CommonOptions: ParsableArguments {
    @Argument(help: "Path to the DICOM file or directory")
    var input: String
    
    @Option(name: .shortAndLong, help: "CoreML model file path (.mlmodel or .mlmodelc)")
    var model: String
    
    @Option(name: .shortAndLong, help: "Output file path (prints to stdout if omitted)")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Output format: json, text, csv, dicom-sr, dicom-seg")
    var format: OutputFormat = .json
    
    @Option(name: .long, help: "Minimum confidence threshold (0.0-1.0)")
    var confidence: Double = 0.5
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    @Flag(name: .long, help: "Verbose output for debugging")
    var verbose: Bool = false
    
    @Option(name: .long, help: "Frame index for multi-frame images (default: 0)")
    var frame: Int = 0
    
    @Flag(name: .long, help: "Enable performance profiling")
    var profile: Bool = false
    
    @Option(name: .long, help: "Output performance metrics to file")
    var profileOutput: String?

    @Option(name: .long, help: ArgumentHelp(
        "Algorithm Version (111003, DCM) written in the dicom-sr output (PS3.16 TID 4019 row 2, M). Default: the model's CoreML version metadata, else \"unknown\"",
        discussion: "Algorithm Name (111001, DCM) is the model file name."))
    var algorithmVersion: String?

    /// TID 4019 row 2 value: `--algorithm-version`, the model's metadata version, or "unknown"
    func resolvedAlgorithmVersion(modelVersion: String?) -> String {
        if let version = algorithmVersion?.trimmingCharacters(in: .whitespaces), !version.isEmpty { return version }
        return modelVersion ?? AIDICOMOutputGenerator.unknownAlgorithmVersion
    }
}

enum OutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
    case json
    case text
    case csv
    case dicomSR = "dicom-sr"
    case dicomSEG = "dicom-seg"
}

// MARK: - Classify Subcommand

struct Classify: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform image classification using AI models",
        discussion: """
            Classify DICOM images using trained CoreML models.
            Outputs class labels with confidence scores.
            
            Example:
              dicom-ai classify chest-xray.dcm --model pneumonia-detector.mlmodel --confidence 0.7
            """
    )
    
    @OptionGroup var options: CommonOptions
    
    @Option(name: .long, help: "Maximum number of results to return")
    var topK: Int = 5
    
    mutating func run() throws {
        #if canImport(CoreML)
        if options.verbose {
            print("Loading DICOM file: \(options.input)")
        }
        
        let fileData = try Data(contentsOf: URL(fileURLWithPath: options.input))
        let dicomFile = try DICOMFile.read(from: fileData, force: options.force)
        let dataSet = dicomFile.dataSet
        
        if options.verbose {
            print("Loading CoreML model: \(options.model)")
        }
        
        let modelURL = URL(fileURLWithPath: options.model)
        let engine = try AIEngine(modelURL: modelURL, verbose: options.verbose)
        
        if options.verbose {
            print("Preprocessing image...")
        }
        
        let inputImage = try engine.preprocessImage(from: dataSet, frameIndex: options.frame)
        
        if options.verbose {
            print("Running inference...")
        }
        
        let predictions = try engine.classify(image: inputImage, topK: topK, threshold: options.confidence)
        
        let output: String
        if options.format == .dicomSR {
            if options.verbose {
                print("Creating DICOM SR from predictions...")
            }
            let srDataSet = try AIDICOMOutputGenerator.createSRFromClassification(
                predictions: predictions,
                sourceDataSet: dataSet,
                modelName: URL(fileURLWithPath: options.model).lastPathComponent,
                algorithmVersion: options.resolvedAlgorithmVersion(modelVersion: engine.modelVersion),
                frameIndex: options.frame
            )
            guard let outputPath = options.output else {
                throw AIError.missingOutput("Output file required for DICOM-SR format")
            }
            let srData = try AIDICOMOutputGenerator.partTenFile(srDataSet)
            try srData.write(to: URL(fileURLWithPath: outputPath))
            output = "DICOM SR saved to \(outputPath)"
        } else {
            output = formatClassificationResults(
                predictions: predictions,
                format: options.format,
                filePath: options.input
            )
        }
        
        try writeOutput(output, to: options.output)
        #else
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
}

// MARK: - Segment Subcommand

struct Segment: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform image segmentation using AI models",
        discussion: """
            Segment anatomical structures or lesions using trained models.
            Outputs segmentation masks in various formats.
            
            Example:
              dicom-ai segment ct.dcm --model organ-seg.mlmodel --output seg.dcm --format dicom-seg
            """
    )
    
    @OptionGroup var options: CommonOptions
    
    @Option(name: .long, help: "Segmentation labels file (JSON with class names)")
    var labels: String?

    @Option(name: .long, help: ArgumentHelp(
        "Segmented Property Category (PS3.16 CID 7150) written for every segment of a dicom-seg output: a keyword or SCHEME:VALUE[:MEANING]. Default: tissue (85756007, SCT, \"Tissue\")",
        discussion: "Keywords: \(SegmentPropertyCodes.keywordList(SegmentPropertyCodes.categories))"))
    var segmentCategory: String = "tissue"

    @Option(name: .long, help: ArgumentHelp(
        "Segmented Property Type (PS3.16 CID 7151) written for every segment of a dicom-seg output: a keyword or SCHEME:VALUE[:MEANING]. Default: tissue (85756007, SCT, \"Tissue\")",
        discussion: "Keywords: \(SegmentPropertyCodes.keywordList(SegmentPropertyCodes.types))"))
    var segmentType: String = "tissue"

    mutating func validate() throws {
        _ = try SegmentPropertyCodes.parse(segmentCategory, from: SegmentPropertyCodes.categories, option: "--segment-category")
        _ = try SegmentPropertyCodes.parse(segmentType, from: SegmentPropertyCodes.types, option: "--segment-type")
    }
    
    mutating func run() throws {
        #if canImport(CoreML)
        if options.verbose {
            print("Loading DICOM file: \(options.input)")
        }
        
        let fileData = try Data(contentsOf: URL(fileURLWithPath: options.input))
        let dicomFile = try DICOMFile.read(from: fileData, force: options.force)
        let dataSet = dicomFile.dataSet
        
        if options.verbose {
            print("Loading CoreML model: \(options.model)")
        }
        
        let modelURL = URL(fileURLWithPath: options.model)
        let engine = try AIEngine(modelURL: modelURL, verbose: options.verbose)
        
        if options.verbose {
            print("Preprocessing image...")
        }
        
        let inputImage = try engine.preprocessImage(from: dataSet, frameIndex: options.frame)
        
        if options.verbose {
            print("Running segmentation...")
        }
        
        let segmentationMask = try engine.segment(image: inputImage)
        
        let output: String
        if options.format == .dicomSEG {
            if options.verbose {
                print("Creating DICOM Segmentation object...")
            }
            let segDICOM = try createDICOMSegmentation(
                sourceDataSet: dataSet,
                segmentationMask: segmentationMask,
                labels: try loadLabels(from: labels),
                modelName: URL(fileURLWithPath: options.model).lastPathComponent,
                category: try SegmentPropertyCodes.parse(segmentCategory, from: SegmentPropertyCodes.categories, option: "--segment-category"),
                type: try SegmentPropertyCodes.parse(segmentType, from: SegmentPropertyCodes.types, option: "--segment-type")
            )
            guard let outputPath = options.output else {
                throw AIError.missingOutput("Output file required for DICOM-SEG format")
            }
            try segDICOM.write(to: URL(fileURLWithPath: outputPath))
            output = "Segmentation saved to \(outputPath)"
        } else {
            output = formatSegmentationResults(
                mask: segmentationMask,
                format: options.format,
                filePath: options.input
            )
        }
        
        try writeOutput(output, to: options.output)
        #else
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
}

// MARK: - Detect Subcommand

struct Detect: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Perform object/lesion detection using AI models",
        discussion: """
            Detect objects or lesions with bounding boxes using trained models.
            
            Example:
              dicom-ai detect mri.dcm --model lesion-detect.mlmodel --confidence 0.7
            """
    )
    
    @OptionGroup var options: CommonOptions
    
    @Option(name: .long, help: "Maximum number of detections to return")
    var maxDetections: Int = 10
    
    @Option(name: .long, help: "IoU threshold for non-maximum suppression")
    var iouThreshold: Double = 0.5
    
    mutating func run() throws {
        #if canImport(CoreML)
        if options.verbose {
            print("Loading DICOM file: \(options.input)")
        }
        
        let fileData = try Data(contentsOf: URL(fileURLWithPath: options.input))
        let dicomFile = try DICOMFile.read(from: fileData, force: options.force)
        let dataSet = dicomFile.dataSet
        
        if options.verbose {
            print("Loading CoreML model: \(options.model)")
        }
        
        let modelURL = URL(fileURLWithPath: options.model)
        let engine = try AIEngine(modelURL: modelURL, verbose: options.verbose)
        
        if options.verbose {
            print("Preprocessing image...")
        }
        
        let inputImage = try engine.preprocessImage(from: dataSet, frameIndex: options.frame)
        
        if options.verbose {
            print("Running detection...")
        }
        
        let detections = try engine.detect(
            image: inputImage,
            confidenceThreshold: options.confidence,
            iouThreshold: iouThreshold,
            maxDetections: maxDetections
        )
        
        let output: String
        if options.format == .dicomSR {
            if options.verbose {
                print("Creating DICOM SR from detections...")
            }
            let srDataSet = try AIDICOMOutputGenerator.createSRFromDetections(
                detections: detections,
                sourceDataSet: dataSet,
                modelName: URL(fileURLWithPath: options.model).lastPathComponent,
                algorithmVersion: options.resolvedAlgorithmVersion(modelVersion: engine.modelVersion),
                frameIndex: options.frame
            )
            guard let outputPath = options.output else {
                throw AIError.missingOutput("Output file required for DICOM-SR format")
            }
            let srData = try AIDICOMOutputGenerator.partTenFile(srDataSet)
            try srData.write(to: URL(fileURLWithPath: outputPath))
            output = "DICOM SR saved to \(outputPath)"
        } else {
            output = formatDetectionResults(
                detections: detections,
                format: options.format,
                filePath: options.input
            )
        }
        
        try writeOutput(output, to: options.output)
        #else
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
}

// MARK: - Enhance Subcommand

struct Enhance: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enhance image quality using AI models",
        discussion: """
            Enhance DICOM images using models trained for denoising,
            super-resolution, or other image enhancement tasks.
            
            Example:
              dicom-ai enhance noisy.dcm --model denoise.mlmodel --output enhanced.dcm
            """
    )
    
    @OptionGroup var options: CommonOptions
    
    mutating func validate() throws {
        guard options.output != nil else {
            throw ValidationError("Output file is required for enhance command")
        }
    }
    
    mutating func run() throws {
        #if canImport(CoreML)
        if options.verbose {
            print("Loading DICOM file: \(options.input)")
        }
        
        let fileData = try Data(contentsOf: URL(fileURLWithPath: options.input))
        let dicomFile = try DICOMFile.read(from: fileData, force: options.force)
        let dataSet = dicomFile.dataSet
        
        if options.verbose {
            print("Loading CoreML model: \(options.model)")
        }
        
        let modelURL = URL(fileURLWithPath: options.model)
        let engine = try AIEngine(modelURL: modelURL, verbose: options.verbose)
        
        if options.verbose {
            print("Preprocessing image...")
        }
        
        let inputImage = try engine.preprocessImage(from: dataSet, frameIndex: options.frame)
        
        if options.verbose {
            print("Running enhancement...")
        }
        
        let enhancedImage = try engine.enhance(image: inputImage)
        
        if options.verbose {
            print("Creating enhanced DICOM file...")
        }
        
        let enhancedDataSet = try createEnhancedDICOM(
            sourceDataSet: dataSet,
            enhancedImage: enhancedImage,
            frameIndex: options.frame,
            modelName: URL(fileURLWithPath: options.model).lastPathComponent
        )
        
        guard let outputPath = options.output else {
            throw AIError.missingOutput("Output file required")
        }
        
        try enhancedDataSet.write(to: URL(fileURLWithPath: outputPath))
        
        let message = "Enhanced image saved to \(outputPath)"
        try writeOutput(message, to: nil)
        #else
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
}

// MARK: - Batch Subcommand

struct Batch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Batch process multiple DICOM files",
        discussion: """
            Process multiple DICOM files efficiently with batch inference.
            
            Example:
              dicom-ai batch series/*.dcm --model classifier.mlmodel --output results.csv --format csv
            """
    )
    
    @Argument(parsing: .captureForPassthrough, help: "DICOM files to process")
    var files: [String] = []
    
    @Option(name: .shortAndLong, help: "CoreML model file path")
    var model: String
    
    @Option(name: .shortAndLong, help: "Output file path")
    var output: String
    
    @Option(name: .shortAndLong, help: "Output format: json, csv")
    var format: BatchOutputFormat = .csv
    
    @Option(name: .long, help: "Batch size for inference")
    var batchSize: Int = 1
    
    @Option(name: .long, help: "Minimum confidence threshold")
    var confidence: Double = 0.5
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    enum BatchOutputFormat: String, ExpressibleByArgument, CaseIterable, Sendable {
        case json
        case csv
    }
    
    mutating func run() throws {
        #if canImport(CoreML)
        guard !files.isEmpty else {
            throw ValidationError("No input files specified")
        }
        
        if verbose {
            print("Processing \(files.count) files with batch size \(batchSize)")
            print("Loading CoreML model: \(model)")
        }
        
        let modelURL = URL(fileURLWithPath: model)
        let engine = try AIEngine(modelURL: modelURL, verbose: verbose)
        
        var allResults: [[String: Any]] = []
        
        for (index, filePath) in files.enumerated() {
            if verbose {
                print("Processing file \(index + 1)/\(files.count): \(filePath)")
            }
            
            do {
                let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
                let dicomFile = try DICOMFile.read(from: fileData, force: force)
                let dataSet = dicomFile.dataSet
                
                let inputImage = try engine.preprocessImage(from: dataSet, frameIndex: 0)
                let predictions = try engine.classify(image: inputImage, topK: 5, threshold: confidence)
                
                let result: [String: Any] = [
                    "file": filePath,
                    "predictions": predictions.map { pred in
                        ["label": pred.label, "confidence": pred.confidence]
                    }
                ]
                
                allResults.append(result)
            } catch {
                if verbose {
                    print("Error processing \(filePath): \(error)")
                }
                allResults.append([
                    "file": filePath,
                    "error": error.localizedDescription
                ])
            }
        }
        
        let outputContent: String
        switch format {
        case .json:
            let jsonData = try JSONSerialization.data(withJSONObject: allResults, options: .prettyPrinted)
            outputContent = String(data: jsonData, encoding: .utf8) ?? ""
        case .csv:
            outputContent = formatBatchResultsAsCSV(allResults)
        }
        
        try outputContent.write(toFile: output, atomically: true, encoding: .utf8)
        
        if verbose {
            print("Results saved to \(output)")
        }
        #else
        throw AIError.platformNotSupported("CoreML is not available on this platform")
        #endif
    }
}

// MARK: - Helper Functions

func writeOutput(_ content: String, to outputPath: String?) throws {
    if let path = outputPath {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    } else {
        print(content)
    }
}

func loadLabels(from path: String?) throws -> [String] {
    guard let path = path else {
        return []
    }
    
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let json = try JSONSerialization.jsonObject(with: data)
    
    if let labels = json as? [String] {
        return labels
    } else if let dict = json as? [String: [String]], let labels = dict["labels"] {
        return labels
    }
    
    throw AIError.invalidLabelsFile("Labels file must contain array of strings")
}

func formatClassificationResults(predictions: [Prediction], format: OutputFormat, filePath: String) -> String {
    switch format {
    case .json:
        let results: [String: Any] = [
            "file": filePath,
            "predictions": predictions.map { ["label": $0.label, "confidence": $0.confidence] }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    case .text:
        var output = "Classification Results for \(filePath):\n"
        for (index, pred) in predictions.enumerated() {
            output += "\(index + 1). \(pred.label): \(String(format: "%.2f%%", pred.confidence * 100))\n"
        }
        return output
    case .csv:
        var csv = "file,label,confidence\n"
        for pred in predictions {
            csv += "\(filePath),\(pred.label),\(pred.confidence)\n"
        }
        return csv
    default:
        return "Format \(format) not supported for classification"
    }
}

func formatSegmentationResults(mask: SegmentationMask, format: OutputFormat, filePath: String) -> String {
    switch format {
    case .json:
        let results: [String: Any] = [
            "file": filePath,
            "mask_size": "\(mask.width)x\(mask.height)",
            "num_classes": mask.numClasses
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    case .text:
        return "Segmentation Results for \(filePath):\nMask Size: \(mask.width)x\(mask.height)\nClasses: \(mask.numClasses)"
    default:
        return "Format \(format) not supported for segmentation"
    }
}

func formatDetectionResults(detections: [Detection], format: OutputFormat, filePath: String) -> String {
    switch format {
    case .json:
        let results: [String: Any] = [
            "file": filePath,
            "detections": detections.map { det in
                [
                    "label": det.label,
                    "confidence": det.confidence,
                    "bbox": [det.bbox.x, det.bbox.y, det.bbox.width, det.bbox.height]
                ]
            }
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    case .text:
        var output = "Detection Results for \(filePath):\n"
        for (index, det) in detections.enumerated() {
            output += "\(index + 1). \(det.label): \(String(format: "%.2f%%", det.confidence * 100)) at (\(det.bbox.x), \(det.bbox.y), \(det.bbox.width), \(det.bbox.height))\n"
        }
        return output
    case .csv:
        var csv = "file,label,confidence,x,y,width,height\n"
        for det in detections {
            csv += "\(filePath),\(det.label),\(det.confidence),\(det.bbox.x),\(det.bbox.y),\(det.bbox.width),\(det.bbox.height)\n"
        }
        return csv
    default:
        return "Format \(format) not supported for detection"
    }
}

func formatBatchResultsAsCSV(_ results: [[String: Any]]) -> String {
    var csv = "file,label,confidence\n"
    for result in results {
        let file = result["file"] as? String ?? ""
        if let predictions = result["predictions"] as? [[String: Any]] {
            for pred in predictions {
                let label = pred["label"] as? String ?? ""
                let confidence = pred["confidence"] as? Double ?? 0.0
                csv += "\(file),\(label),\(confidence)\n"
            }
        } else if let error = result["error"] as? String {
            csv += "\(file),ERROR,\(error)\n"
        }
    }
    return csv
}

func createDICOMSegmentation(
    sourceDataSet: DataSet,
    segmentationMask: SegmentationMask,
    labels: [String],
    modelName: String = "AI Model",
    category: CodedConcept = SegmentPropertyCodes.defaultCategory,
    type: CodedConcept = SegmentPropertyCodes.defaultType
) throws -> Data {
    return try AIDICOMOutputGenerator.createSegmentationObject(
        sourceDataSet: sourceDataSet,
        segmentationMask: segmentationMask,
        labels: labels,
        modelName: modelName,
        category: category,
        type: type
    )
}

func createEnhancedDICOM(sourceDataSet: DataSet, enhancedImage: ProcessedImage, frameIndex: Int, modelName: String) throws -> Data {
    return try AIDICOMOutputGenerator.createEnhancedDICOMFile(
        sourceDataSet: sourceDataSet,
        enhancedImage: enhancedImage,
        frameIndex: frameIndex,
        modelName: modelName
    )
}

// MARK: - Registry Subcommand

@available(macOS 14.0, iOS 17.0, *)
struct Registry: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage AI model registry",
        discussion: """
            Manage the AI model registry for versioning and tracking models.
            
            Examples:
              dicom-ai registry add --name pneumonia-v1 --path model.mlmodel --type classification
              dicom-ai registry list
              dicom-ai registry remove --name pneumonia-v1
              dicom-ai registry search --tags chest,xray
            """,
        subcommands: [
            RegistryAdd.self,
            RegistryList.self,
            RegistryRemove.self,
            RegistrySearch.self,
            RegistryInfo.self,
            RegistryClear.self,
        ]
    )
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistryAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a model to the registry"
    )
    
    @Option(name: .shortAndLong, help: "Model name")
    var name: String
    
    @Option(name: .long, help: "Model path (.mlmodel or .mlmodelc)")
    var path: String
    
    @Option(name: .long, help: "Model version (e.g., 1.0.0)")
    var version: String = "1.0.0"
    
    @Option(name: .long, help: "Model type: classification, segmentation, detection, enhancement, other")
    var type: String
    
    @Option(name: .long, help: "Model description")
    var description: String?
    
    @Option(name: .long, help: "Input width")
    var inputWidth: Int?
    
    @Option(name: .long, help: "Input height")
    var inputHeight: Int?
    
    @Option(name: .long, help: "Output type: classification, segmentation, detection, image, multiArray")
    var outputType: String = "classification"
    
    @Option(name: .long, help: "Tags (comma-separated)")
    var tags: String?
    
    @Flag(name: .long, help: "Overwrite if model already exists")
    var overwrite: Bool = false
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let registry = try ModelRegistry(verbose: verbose)
        
        // Parse model type
        guard let modelType = parseModelType(type) else {
            throw ValidationError("Invalid model type: \(type)")
        }
        
        // Parse output type
        guard let outType = parseOutputType(outputType) else {
            throw ValidationError("Invalid output type: \(outputType)")
        }
        
        // Parse tags
        let tagList = tags?.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) } ?? []
        
        // Create input size if provided
        let inputSize: ModelRegistry.ModelEntry.ModelInputSize?
        if let width = inputWidth, let height = inputHeight {
            inputSize = ModelRegistry.ModelEntry.ModelInputSize(width: width, height: height)
        } else {
            inputSize = nil
        }
        
        let entry = ModelRegistry.ModelEntry(
            name: name,
            version: version,
            path: path,
            modelType: modelType,
            description: description,
            inputSize: inputSize,
            outputType: outType,
            tags: tagList
        )
        
        try registry.add(entry, overwrite: overwrite)
        
        print("✓ Model '\(name)' (version \(version)) added to registry")
    }
    
    private func parseModelType(_ type: String) -> ModelRegistry.ModelEntry.ModelType? {
        switch type.lowercased() {
        case "classification": return .classification
        case "segmentation": return .segmentation
        case "detection": return .detection
        case "enhancement": return .enhancement
        case "other": return .other
        default: return nil
        }
    }
    
    private func parseOutputType(_ type: String) -> ModelRegistry.ModelEntry.ModelOutputType? {
        switch type.lowercased() {
        case "classification": return .classification
        case "segmentation": return .segmentation
        case "detection": return .detection
        case "image": return .image
        case "multiarray": return .multiArray
        default: return nil
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistryList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all models in the registry"
    )
    
    @Option(name: .long, help: "Filter by model type")
    var type: String?
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let registry = try ModelRegistry(verbose: verbose)
        
        let filterType: ModelRegistry.ModelEntry.ModelType?
        if let typeStr = type {
            filterType = parseModelType(typeStr)
        } else {
            filterType = nil
        }
        
        let entries = registry.list(filterByType: filterType)
        
        if entries.isEmpty {
            print("No models in registry")
            return
        }
        
        print("Models in registry (\(entries.count)):\n")
        
        for entry in entries {
            print("Name: \(entry.name)")
            print("Version: \(entry.version)")
            print("Type: \(entry.modelType.rawValue)")
            print("Path: \(entry.path)")
            
            if let desc = entry.description {
                print("Description: \(desc)")
            }
            
            if let size = entry.inputSize {
                print("Input Size: \(size.width)×\(size.height)")
            }
            
            print("Output Type: \(entry.outputType.rawValue)")
            
            if !entry.tags.isEmpty {
                print("Tags: \(entry.tags.joined(separator: ", "))")
            }
            
            print("Added: \(formatDate(entry.dateAdded))")
            
            if let lastUsed = entry.lastUsed {
                print("Last Used: \(formatDate(lastUsed))")
            }
            
            print()
        }
    }
    
    private func parseModelType(_ type: String) -> ModelRegistry.ModelEntry.ModelType? {
        switch type.lowercased() {
        case "classification": return .classification
        case "segmentation": return .segmentation
        case "detection": return .detection
        case "enhancement": return .enhancement
        case "other": return .other
        default: return nil
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistryRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a model from the registry"
    )
    
    @Option(name: .shortAndLong, help: "Model name")
    var name: String
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let registry = try ModelRegistry(verbose: verbose)
        try registry.remove(name: name)
        
        print("✓ Model '\(name)' removed from registry")
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistrySearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search models by tags"
    )
    
    @Option(name: .long, help: "Tags to search for (comma-separated)")
    var tags: String
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let registry = try ModelRegistry(verbose: verbose)
        
        let tagList = tags.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        let entries = registry.search(tags: tagList)
        
        if entries.isEmpty {
            print("No models found with tags: \(tagList.joined(separator: ", "))")
            return
        }
        
        print("Found \(entries.count) model(s):\n")
        
        for entry in entries {
            print("\(entry.name) (v\(entry.version)) - \(entry.modelType.rawValue)")
            if let desc = entry.description {
                print("  \(desc)")
            }
            print()
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistryInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Get detailed information about a model"
    )
    
    @Option(name: .shortAndLong, help: "Model name")
    var name: String
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        let registry = try ModelRegistry(verbose: verbose)
        
        guard let entry = registry.get(name: name) else {
            print("Model '\(name)' not found in registry")
            throw ExitCode.failure
        }
        
        print("Model: \(entry.name)")
        print("Version: \(entry.version)")
        print("Type: \(entry.modelType.rawValue)")
        print("Output Type: \(entry.outputType.rawValue)")
        print("Path: \(entry.path)")
        
        if let desc = entry.description {
            print("Description: \(desc)")
        }
        
        if let size = entry.inputSize {
            print("Input Size: \(size.width)×\(size.height)")
        }
        
        if !entry.tags.isEmpty {
            print("Tags: \(entry.tags.joined(separator: ", "))")
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        print("Date Added: \(formatter.string(from: entry.dateAdded))")
        
        if let lastUsed = entry.lastUsed {
            print("Last Used: \(formatter.string(from: lastUsed))")
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
struct RegistryClear: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear all models from the registry"
    )
    
    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Confirm clearing the registry")
    var confirm: Bool = false
    
    mutating func run() throws {
        if !confirm {
            print("This will remove all models from the registry.")
            print("Use --confirm to proceed.")
            throw ExitCode.failure
        }
        
        let registry = try ModelRegistry(verbose: verbose)
        try registry.clear()
        
        print("✓ Registry cleared")
    }
}

// MARK: - Main Entry Point

#if canImport(CoreML) || canImport(Vision)
if #available(macOS 14.0, iOS 17.0, *) {
    DICOMAI.main()
} else {
    fatalError("This tool requires macOS 14.0, iOS 17.0, or later")
}
#else
print("✗ CoreML or Vision framework not available on this platform")
#endif
