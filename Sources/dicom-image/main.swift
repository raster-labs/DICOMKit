// NEMA-verified: 2026a, checked 2026-10-01 — output diffed against PS3.3 2026a Table A.8-1 (Secondary Capture Image IOD): all Type 1/2 attributes of the 9 M modules present (27 grayscale, 28 colour incl. Planar Configuration 1C; Tables C.7-1, C.7-3, C.7-5a, C.8-24, C.7.10.1-1, C.7-9, C.7-11a/c, C.8-25, C.12-1); 16 options: value options refused (exit 1) when PS3.5 2026a Table 6.2-1 / Section 9 forbids them (P-IMAGE-VR); --modality via ModalityOptionValidator (C.7.3.1.1.1, 97 terms), --conversion-type Table C.8-24 (8 terms), SOP Class name/UID per PS3.4 Table B.5-1 and PS3.6 Table A-1, help names per PS3.6 Table 6-1 (DICOMKit ImageConverter.OutputRules, D274)
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

// The image→Secondary-Capture conversion engine now lives in the DICOMKit library
// (Sources/DICOMKit/SecondaryCapture/ImageConverter.swift) so the CLI and
// DICOMStudio run the same code. This CLI handles argument parsing, file/directory
// orchestration, output paths, and summaries; ImageConverter does the per-image
// pixel extraction, EXIF mapping, and Secondary Capture assembly.

struct DICOMImage: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-image",
        abstract: "Convert standard images to DICOM Secondary Capture Image instances",
        discussion: """
            Convert JPEG, PNG, TIFF, and other image formats to the DICOM Secondary
            Capture Image IOD (PS3.3 A.8.1), SOP Class "Secondary Capture Image Storage"
            (1.2.840.10008.5.1.4.1.1.7), Explicit VR Little Endian. Pixels are written as
            8-bit RGB (Planar Configuration 0) or MONOCHROME2. Supports EXIF metadata
            extraction and batch conversion.

            Supported formats: JPEG, PNG, TIFF, BMP, GIF (depends on platform support)

            Values the written VR cannot hold (PS3.5 Table 6.2-1: LO and PN over 64
            characters or with a backslash, IS outside -2^31..2^31-1, a UID breaking PS3.5
            Section 9) are refused with exit status 1 and nothing is written.

            Examples:
              # Convert JPEG to DICOM
              dicom-image photo.jpg --output capture.dcm \\
                --patient-name "DOE^JOHN" \\
                --patient-id "12345"

              # Convert with EXIF metadata
              dicom-image photo.jpg --output capture.dcm \\
                --patient-name "SMITH^JANE" \\
                --patient-id "54321" \\
                --use-exif \\
                --study-description "Clinical Photography"

              # Batch convert images
              dicom-image photos/ --output dicoms/ --recursive \\
                --patient-name "BATCH^PATIENT" \\
                --patient-id "BATCH001" \\
                --series-description "Clinical Photos"

              # Convert multi-page TIFF
              dicom-image multipage.tiff --output frames/ \\
                --split-pages \\
                --patient-name "TEST^PATIENT" \\
                --patient-id "99999"
            """,
        version: "1.1.6"
    )

    @Argument(help: "Input image file or directory")
    var input: String

    @Option(name: .shortAndLong, help: "Output file or directory path")
    var output: String?

    @Option(name: .long, help: "Patient's Name (0010,0010), PN, e.g. 'DOE^JOHN' (at most 64 characters per component group, no backslash)")
    var patientName: String?

    @Option(name: .long, help: "Patient ID (0010,0020), LO (at most 64 characters, no backslash)")
    var patientId: String?

    @Option(name: .long, help: "Study Description (0008,1030), LO (at most 64 characters, no backslash)")
    var studyDescription: String?

    @Option(name: .long, help: "Series Description (0008,103E), LO (at most 64 characters, no backslash)")
    var seriesDescription: String?

    @Option(name: .long, help: "Study Instance UID (0020,000D), UI per PS3.5 Section 9 (generated if not provided)")
    var studyUid: String?

    @Option(name: .long, help: "Series Instance UID (0020,000E), UI per PS3.5 Section 9 (generated if not provided)")
    var seriesUid: String?

    @Option(name: .long, help: "Series Number (0020,0011), IS (written empty if not provided; Type 2)")
    var seriesNumber: Int?

    @Option(name: .long, help: "Instance Number (0020,0013), IS (default 1; starting value for batch and TIFF pages)")
    var instanceNumber: Int?

    @Option(name: .long, help: ArgumentHelp(stringLiteral: ModalityOptionValidator.helpText("to write (default: OT)")))
    var modality: String?

    @Flag(name: .long, help: "Reject a --modality value that is not a current DICOM Defined Term")
    var strictModality: Bool = false

    @Option(name: .long, help: "Conversion Type (0008,0064): DV, DI, DF, WSD, SD, SI, DRW or SYN (PS3.3 Table C.8-24; default: WSD)")
    var conversionType: String?

    @Flag(name: .long, help: "Use EXIF metadata: DateTimeOriginal -> Acquisition Date/Time (0008,0022/0032), DPI -> Nominal Scanned Pixel Spacing (0018,2010), description -> Study Description")
    var useExif: Bool = false

    @Flag(name: .long, help: "Write each page of a multi-page TIFF as its own Secondary Capture instance")
    var splitPages: Bool = false

    @Flag(name: .long, help: "Process directories recursively")
    var recursive: Bool = false

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        #if canImport(CoreGraphics)
        guard ImageConverter.OutputRules.conversionType(conversionType) != nil else {
            throw ValidationError("--conversion-type '\(conversionType ?? "")' is not a Defined Term of PS3.3 Table C.8-24 "
                + "(\(ConversionType.definedTerms.joined(separator: ", ")))")
        }
        // P-IMAGE-VR: a value the written VR cannot hold is refused (exit 1), not written.
        let violations = ImageConverter.OutputRules.valueViolations(
            patientName: patientName, patientID: patientId,
            studyDescription: studyDescription, seriesDescription: seriesDescription,
            studyUID: studyUid, seriesUID: seriesUid,
            seriesNumber: seriesNumber, instanceNumber: instanceNumber)
        if !violations.isEmpty {
            for line in violations {
                FileHandle.standardError.write(Data(("Error: " + line + "\n").utf8))
            }
            throw ExitCode.failure
        }
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input path not found: \(input)")
        }

        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            guard recursive else {
                throw ValidationError("Directory processing requires --recursive flag")
            }
            try convertDirectory(inputPath: input, outputPath: output)
        } else {
            try convertFile(inputPath: input, outputPath: output)
        }
        #else
        throw ValidationError("Image conversion not supported on this platform")
        #endif
    }

    #if canImport(CoreGraphics)
    private func metadata(studyUID: String, seriesUID: String, instanceNumber: Int,
                          patientName: String, patientID: String) throws -> ImageConverter.Metadata {
        // Throws rather than defaulting on a bad value: --strict-modality has to
        // be able to stop the run, and this is where the value is consumed.
        let resolved = try ModalityOptionValidator.resolve(
            modality, strict: strictModality, verbose: verbose)
        return ImageConverter.Metadata(
            patientName: patientName, patientID: patientID,
            studyUID: studyUID, seriesUID: seriesUID, instanceNumber: instanceNumber,
            studyDescription: studyDescription, seriesDescription: seriesDescription,
            modality: resolved ?? Modality.ot.rawValue,
            seriesNumber: seriesNumber,
            conversionType: ImageConverter.OutputRules.conversionType(conversionType) ?? .workstation)
    }

    // MARK: - Directory Processing

    private func convertDirectory(inputPath: String, outputPath: String?) throws {
        let inputURL = URL(fileURLWithPath: inputPath)

        let outputDirURL: URL
        if let specifiedOutput = outputPath {
            outputDirURL = URL(fileURLWithPath: specifiedOutput)
        } else {
            outputDirURL = inputURL.appendingPathComponent("dicom")
        }

        try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)

        if verbose {
            print(ImageConsole.batchHeader(inputPath: inputPath, outputDir: outputDirURL.path), terminator: "")
        }

        guard let patientName = patientName, !patientName.isEmpty else {
            throw ValidationError("Patient Name is required for batch conversion (--patient-name)")
        }
        guard let patientId = patientId, !patientId.isEmpty else {
            throw ValidationError("Patient ID is required for batch conversion (--patient-id)")
        }

        var successCount = 0
        var failureCount = 0
        var instanceNum = instanceNumber ?? 1

        let finalStudyUID = studyUid ?? ImageConverter.generateUID()
        let finalSeriesUID = seriesUid ?? ImageConverter.generateUID()

        let fileURLs = FileGatherer.regularFiles(under: inputURL) ?? []

        for fileURL in fileURLs {
            guard ImageConverter.isImageFile(fileURL) else {
                if verbose {
                    print(ImageConsole.skippedLine(fileName: fileURL.lastPathComponent))
                }
                continue
            }

            do {
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let outputFileURL = outputDirURL.appendingPathComponent("\(baseName).dcm")

                let data = try ImageConverter.secondaryCaptureData(
                    imageURL: fileURL,
                    metadata: metadata(studyUID: finalStudyUID, seriesUID: finalSeriesUID,
                                       instanceNumber: instanceNum, patientName: patientName, patientID: patientId),
                    useExif: useExif)
                try ImageConverter.OutputRules.finalize(data).write(to: outputFileURL)

                successCount += 1
                instanceNum += 1

                if verbose {
                    print(ImageConsole.fileSuccessLine(inputName: fileURL.lastPathComponent, outputName: outputFileURL.lastPathComponent))
                }
            } catch {
                failureCount += 1
                if verbose {
                    print(ImageConsole.fileFailureLine(inputName: fileURL.lastPathComponent, message: error.localizedDescription))
                }
            }
        }

        print(ImageConsole.batchSummary(
            successful: successCount, failed: failureCount,
            studyUID: finalStudyUID, seriesUID: finalSeriesUID, outputDir: outputDirURL.path
        ), terminator: "")
    }

    // MARK: - File Processing

    private func convertFile(inputPath: String, outputPath: String?) throws {
        let inputURL = URL(fileURLWithPath: inputPath)

        guard let patientName = patientName, !patientName.isEmpty else {
            throw ValidationError("Patient Name is required for conversion (--patient-name)")
        }
        guard let patientId = patientId, !patientId.isEmpty else {
            throw ValidationError("Patient ID is required for conversion (--patient-id)")
        }

        if splitPages && (inputURL.pathExtension.lowercased() == "tiff" || inputURL.pathExtension.lowercased() == "tif") {
            try convertMultiPageTIFF(inputURL: inputURL, outputPath: outputPath,
                                     patientName: patientName, patientID: patientId)
        } else {
            let finalOutputPath: String
            if let specifiedOutput = outputPath {
                finalOutputPath = specifiedOutput
            } else {
                finalOutputPath = inputURL.deletingPathExtension().appendingPathExtension("dcm").path
            }

            let outputURL = URL(fileURLWithPath: finalOutputPath)

            if verbose {
                print(ImageConsole.convertingLine(inputPath: inputPath))
            }

            let data = try ImageConverter.secondaryCaptureData(
                imageURL: inputURL,
                metadata: metadata(studyUID: studyUid ?? ImageConverter.generateUID(),
                                   seriesUID: seriesUid ?? ImageConverter.generateUID(),
                                   instanceNumber: instanceNumber ?? 1,
                                   patientName: patientName, patientID: patientId),
                useExif: useExif)
            try ImageConverter.OutputRules.finalize(data).write(to: outputURL)

            print(ImageConsole.convertedLine(outputPath: finalOutputPath, verbose: verbose))
        }
    }

    // MARK: - Multi-Page TIFF Handling

    private func convertMultiPageTIFF(inputURL: URL, outputPath: String?, patientName: String, patientID: String) throws {
        let pageCount = try ImageConverter.pageCount(of: inputURL)
        guard pageCount > 0 else {
            throw ImageConversionError.noPages
        }

        let outputDirURL: URL
        if let specifiedOutput = outputPath {
            outputDirURL = URL(fileURLWithPath: specifiedOutput)
        } else {
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            outputDirURL = inputURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_frames")
        }

        try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)

        if verbose {
            print(ImageConsole.tiffHeader(fileName: inputURL.lastPathComponent, pages: pageCount, outputDir: outputDirURL.path), terminator: "")
        }

        let finalStudyUID = studyUid ?? ImageConverter.generateUID()
        let finalSeriesUID = seriesUid ?? ImageConverter.generateUID()

        for pageIndex in 0..<pageCount {
            let outputFileName = String(format: "frame_%04d.dcm", pageIndex + 1)
            let outputFileURL = outputDirURL.appendingPathComponent(outputFileName)

            do {
                let data = try ImageConverter.secondaryCaptureData(
                    imageURL: inputURL,
                    pageIndex: pageIndex,
                    metadata: metadata(studyUID: finalStudyUID, seriesUID: finalSeriesUID,
                                       instanceNumber: (instanceNumber ?? 1) + pageIndex,
                                       patientName: patientName, patientID: patientID),
                    // Honor --use-exif per page: ImageConverter reads each page's
                    // own EXIF via CGImageSourceCopyPropertiesAtIndex(pageIndex).
                    useExif: useExif)
                try ImageConverter.OutputRules.finalize(data).write(to: outputFileURL)

                if verbose {
                    print(ImageConsole.pageSuccessLine(page: pageIndex + 1, outputName: outputFileName))
                }
            } catch {
                if verbose {
                    print(ImageConsole.pageFailureLine(page: pageIndex + 1, message: error.localizedDescription))
                }
            }
        }

        print(ImageConsole.tiffSummary(pages: pageCount, outputDir: outputDirURL.path), terminator: "")
    }
    #endif
}

DICOMImage.main()
