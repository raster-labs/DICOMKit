// NEMA-verified: 2026a, checked 2026-10-01 — 14 options classified against PS3.6 2026a Table A-1 (--transfer-syntax: 25 catalog targets, 21 UIDs; all 21 A-1 keywords select their A-1 UID — JPEG2000Lossless / HTJ2KLossless / JPEGXLLossless now .90 / .201 / .110 with a stderr note, old meaning renamed …Reversible (P-CONVERT-TS-KEYWORDS); 7 keywords folded into DICOMConverter.additionalTableA1Keywords, D268), PS3.3 C.11.2.1.2.1 (--window-width ≥ 1, now enforced), Table 10-3 ("The first Frame shall be denoted as Frame number 1": new 1-based --frame-number, 0-based --frame deprecated, P-CONVERT-FRAME), PS3.5 7.8 (--strip-private, engine deferred), PS3.10 7.1 (--force); directory run exits 1 when a file failed (P-CONVERT-EXIT); DICOM output checked on fixtures against PS3.3 C.7.6.1.1.5 and PS3.5 8.2, 8.2.4 (engine findings deferred)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@main
struct DICOMConvert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-convert",
        abstract: "Convert DICOM files between transfer syntaxes and export to image formats",
        discussion: """
            Convert DICOM files to different transfer syntaxes or export pixel data to PNG, JPEG, or TIFF.
            Supports both single file and batch directory conversion.

            Frames are numbered from 1 (PS3.3 Table 10-3); select one with --frame-number.
            Exit codes: 0 success; 1 a file failed (a directory run exits 1 when any file
            failed) or --frame and --frame-number were both given; 64 invalid arguments.
            
            Examples:
              dicom-convert file.dcm --output output.dcm --transfer-syntax ExplicitVRLittleEndian
              dicom-convert ct.dcm --output ct.png --apply-window --window-center 40 --window-width 400
              dicom-convert input/ --output output/ --transfer-syntax ExplicitVRLittleEndian --recursive
              dicom-convert xray.dcm --output xray.jpg --format jpeg --quality 95
              dicom-convert cine.dcm --output frame3.png --frame-number 3
            """,
        version: "1.0.0"
    )
    
    @Argument(help: "Path to DICOM file or directory")
    var inputPath: String
    
    @Option(name: .shortAndLong, help: "Output file or directory path")
    var output: String
    
    @Option(name: .long, help: "\(DICOMConverter.transferSyntaxOptionHelpWithKeywords)")
    var transferSyntax: String?
    
    @Option(name: .long, help: "Output format for image export: png, jpeg, tiff, dicom (default: dicom)")
    var format: ExportFormat = .dicom
    
    @Option(name: .long, help: "JPEG quality (1-100, default: 90)")
    var quality: Int = 90
    
    @Flag(name: .long, help: "Apply window/level during export")
    var applyWindow: Bool = false
    
    @Option(name: .long, help: "Window center value (Window Center (0028,1050))")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window width value (Window Width (0028,1051), at least 1)")
    var windowWidth: Double?
    
    @Option(name: .long, help: "Frame to export, numbered from 1 (PS3.3 Table 10-3: the first Frame is Frame number 1; default 1)")
    var frameNumber: Int?

    @Option(name: .long, help: "deprecated: 0-based index; use --frame-number")
    var frame: Int?
    
    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false
    
    @Flag(name: .long, help: "Strip private tags during conversion")
    var stripPrivate: Bool = false
    
    // Spelled `--validate`; the property has another name so the command can declare
    // ArgumentParser's `validate()` hook.
    @Flag(name: .customLong("validate"), help: "Validate output after conversion")
    var validateOutput: Bool = false
    
    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false
    
    mutating func validate() throws {
        // Documented range of --quality.
        guard (1...100).contains(quality) else {
            throw ValidationError("--quality must be between 1 and 100")
        }
        // PS3.3 2026a C.11.2.1.2.1: "Window Width (0028,1051) shall always be greater than
        // or equal to 1."
        if let width = windowWidth, width < 1 {
            throw ValidationError("--window-width must be at least 1 (Window Width (0028,1051), PS3.3 C.11.2.1.2.1)")
        }
        if let f = frame, f < 0 {
            throw ValidationError("--frame is a 0-based frame index and must be 0 or more")
        }
        if let n = frameNumber, n < 1 {
            throw ValidationError("--frame-number must be 1 or more (PS3.3 Table 10-3: the first Frame is Frame number 1)")
        }
        // Both spellings at once: refused with exit 1 (not a usage error).
        if frame != nil && frameNumber != nil {
            throw FrameSelectionConflict()
        }
    }

    /// 0-based index of the frame to export: --frame-number − 1, else the deprecated
    /// 0-based --frame, else the first frame.
    var frameIndex: Int { frameNumber.map { $0 - 1 } ?? frame ?? 0 }

    mutating func run() async throws {
        if frame != nil {
            FileHandle.standardError.write(Data("warning: --frame is deprecated (0-based index); use --frame-number (numbered from 1, PS3.3 Table 10-3)\n".utf8))
        }
        if let token = transferSyntax, let note = TransferSyntax.reassignedKeywordNote(for: token) {
            FileHandle.standardError.write(Data((note + "\n").utf8))
        }
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: output)
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputPath, isDirectory: &isDirectory) else {
            throw ValidationError("Input path not found: \(inputPath)")
        }
        
        if isDirectory.boolValue {
            try convertDirectory(input: inputURL, output: outputURL)
        } else {
            // `--output` may name a directory (the Workshop's Browse button hands one back,
            // and `~/Desktop/DICOM_Output/` is the natural thing to type). Resolve it to a
            // concrete file through the SAME helper the app and the other CLIs use, or the
            // write below fails with "Is a directory".
            let destination = URL(fileURLWithPath: OutputPathResolver.resolveFileOutput(
                output: output, input: inputPath, fileExtension: format.fileExtension))
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try convertFile(input: inputURL, output: destination)
            } catch {
                // Same failure report as DICOMStudio's Workshop (shared ConvertConsole).
                FileHandle.standardError.write(Data(ConvertConsole.failureReport(for: error).utf8))
                throw ExitCode.failure
            }
        }
    }
    
    private func convertDirectory(input: URL, output: URL) throws {
        guard recursive else {
            throw ValidationError("Directory conversion requires --recursive flag")
        }
        
        // Create output directory if needed
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        
        // Shared, sorted directory walk — the same gatherer the Workshop uses, so
        // both surfaces convert the same files in the same order.
        guard let fileURLs = FileGatherer.regularFiles(under: input) else {
            throw ValidationError("Failed to enumerate directory: \(input.path)")
        }

        var fileCount = 0
        var successCount = 0
        var errorCount = 0

        for fileURL in fileURLs {
            fileCount += 1
            
            // Calculate relative path
            let relativePath = fileURL.path.replacingOccurrences(of: input.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            var outputFileURL = output.appendingPathComponent(relativePath)
            // Image formats must not keep the source `.dcm` extension: the bytes are
            // PNG/JPEG/TIFF, so retag the file to match its contents (the single-file
            // path already does this via OutputPathResolver). `.dicom` keeps its name.
            if format != .dicom {
                outputFileURL.deletePathExtension()
                outputFileURL.appendPathExtension(format.fileExtension)
            }
            
            // Create intermediate directories
            let outputDir = outputFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            do {
                try convertFile(input: fileURL, output: outputFileURL)
                successCount += 1
                print(ConvertConsole.batchProgressLine(success: true, relativePath: relativePath, error: nil), terminator: "")
            } catch {
                errorCount += 1
                print(ConvertConsole.batchProgressLine(success: false, relativePath: relativePath, error: ConvertConsole.failureSummary(for: error)), terminator: "")
            }
        }

        print(ConvertConsole.batchSummary(succeeded: successCount, total: fileCount, failed: errorCount), terminator: "")
        // Like dicom-compress batch: a run with any failed file is a failure.
        if errorCount > 0 {
            throw ExitCode.failure
        }
    }
    
    private func convertFile(input: URL, output: URL) throws {
        let fileData = try Data(contentsOf: input)
        
        // Read DICOM file
        let dicomFile = try DICOMFile.read(from: fileData, force: force)
        
        // Process based on output format
        switch format {
        case .dicom:
            try convertTransferSyntax(dicomFile: dicomFile, output: output)
        case .png, .jpeg, .tiff:
            try exportImage(dicomFile: dicomFile, output: output)
        }
        
        // Validate if requested
        if validateOutput && format == .dicom {
            let outputData = try Data(contentsOf: output)
            _ = try DICOMFile.read(from: outputData, force: false)
        }
    }
    
    private func convertTransferSyntax(dicomFile: DICOMFile, output: URL) throws {
        guard let transferSyntaxName = transferSyntax else {
            throw ValidationError(DICOMConverter.missingTargetMessage)
        }

        let targetEncoding = try parseTransferSyntax(transferSyntaxName)

        // Shared process → output pipeline (identical bytes in CLI and app). The resolved
        // intent drives reversible-vs-irreversible encoding into the general UIDs and the
        // Lossy Image Compression provenance attributes.
        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: dicomFile,
            to: targetEncoding,
            stripPrivate: stripPrivate
        )

        try outcome.data.write(to: output)

        // Result line via the SHARED ConvertConsole (DICOMKit) — the same builder
        // the Workshop executor uses, so app and CLI stay text-exact.
        print(ConvertConsole.transcodeLine(
            wasTranscoded: outcome.wasTranscoded,
            sourceUID: outcome.sourceSyntax.uid, targetUID: outcome.targetSyntax.uid,
            isLossless: outcome.isLossless), terminator: "")
    }
    
    private func exportImage(dicomFile: DICOMFile, output: URL) throws {
        #if canImport(CoreGraphics)
        // Extract pixel data
        let pixelData = try dicomFile.tryPixelData()

        let frameIndex = self.frameIndex
        guard frameIndex >= 0 && frameIndex < pixelData.descriptor.numberOfFrames else {
            if let number = frameNumber {
                throw ConversionError.invalidFrameNumber(number, pixelData.descriptor.numberOfFrames)
            }
            throw ConversionError.invalidFrame(frameIndex, pixelData.descriptor.numberOfFrames)
        }

        guard let imageFormat = format.exportImageFormat else {
            throw ConversionError.exportFailed
        }

        // Shared render (incl. window resolution) + shared encode → identical raster in CLI and app.
        let image = try DICOMImageExporter.renderFrameForExport(
            file: dicomFile, pixelData: pixelData, frameIndex: frameIndex,
            applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth
        )
        try DICOMImageExporter.exportCGImage(
            image, to: output, format: imageFormat, quality: quality, metadata: nil
        )
        #else
        throw ConversionError.unsupportedPlatform
        #endif
    }

    private func parseTransferSyntax(_ name: String) throws -> SelectableEncoding {
        // Single source of truth: the shared DICOMConverter target catalog (DICOMKit).
        // Resolve the full encoding (UID + intent) so `…-lossless` names encode reversibly
        // into the general UID and `…-lossy` names carry the lossy provenance.
        guard let encoding = DICOMConverter.resolveTargetEncoding(name) else {
            throw ValidationError(DICOMConverter.unknownTargetMessage(name))
        }
        return encoding
    }
}

enum ExportFormat: String, ExpressibleByArgument {
    case dicom
    case png
    case jpeg
    case tiff

    /// Maps to the shared image-export format, or `nil` for `.dicom` (handled by the
    /// transfer-syntax path, not the image exporter).
    var exportImageFormat: ExportImageFormat? {
        switch self {
        case .dicom: return nil
        case .png:   return .png
        case .jpeg:  return .jpeg
        case .tiff:  return .tiff
        }
    }

    /// Extension given to the produced file when `--output` names a directory.
    /// Delegates to the shared `ConvertConsole` map so the CLI and the app's
    /// Workshop executor cannot drift apart on output extensions.
    var fileExtension: String {
        ConvertConsole.fileExtension(forFormat: rawValue)
    }
}

enum ConversionError: LocalizedError {
    case noPixelData
    case invalidFrame(Int, Int)
    case invalidFrameNumber(Int, Int)
    case renderFailed
    case exportFailed
    case unsupportedPlatform
    
    var errorDescription: String? {
        switch self {
        case .noPixelData:
            return "No pixel data found in DICOM file"
        case .invalidFrame(let requested, let total):
            return DICOMConverter.invalidFrameMessage(requested: requested, total: total)
        case .invalidFrameNumber(let requested, let total):
            return DICOMConverter.invalidFrameNumberMessage(requested: requested, total: total)
        case .renderFailed:
            return "Failed to render pixel data to image"
        case .exportFailed:
            return "Failed to export image to file"
        case .unsupportedPlatform:
            return "Image export is not supported on this platform"
        }
    }
}

/// `--frame` and `--frame-number` given together. Not a `ValidationError`, so the command
/// exits 1 with this message.
struct FrameSelectionConflict: LocalizedError, CustomStringConvertible {
    var description: String {
        "--frame (deprecated, 0-based) and --frame-number (numbered from 1) cannot be used together"
    }
    var errorDescription: String? { description }
}
