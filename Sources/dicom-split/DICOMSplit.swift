// NEMA-verified: 2026a, checked 2026-10-01 — help names checked by script: 9 SOP Class names quoted in full and 2 abbreviated lists (Enhanced CT/MR/PET/XA/XRF, Legacy Converted Enhanced CT/MR/PET) against PS3.6 2026a Table A-1, 7 attribute names/tags (Instance Number, Stack ID, In-Stack Position Number, Temporal Position Index, Series Instance UID, Shared/Per-Frame Functional Groups Sequence) against Table 6-1; --frame-numbers takes Frame numbers from 1 (PS3.3 C.7.6.16.1.2 "Frames are implicitly numbered starting from 1"), the 0-based --frames is deprecated (P-SPLIT-1); verbose progress labels say Frame number N; Explicit VR Little Endian per Table A-1
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary

@main
struct DICOMSplit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-split",
        abstract: "Extract individual frames from multi-frame DICOM files",
        discussion: """
            Extracts individual frames from multi-frame DICOM files. Enhanced
            CT/MR/PET/XA/XRF and Legacy Converted Enhanced CT/MR/PET Image Storage
            objects become single-frame CT Image Storage, MR Image Storage, Positron
            Emission Tomography Image Storage, X-Ray Angiographic Image Storage or X-Ray
            Radiofluoroscopic Image Storage instances, with the Shared and Per-Frame
            Functional Groups Sequences flattened to the top level; Ultrasound
            Multi-frame Image Storage and the Multi-frame Secondary Capture classes
            become Ultrasound Image Storage / Secondary Capture Image Storage with the
            cine vectors resolved; Nuclear Medicine, X-Ray Angiographic, X-Ray
            Radiofluoroscopic, RT Image, Breast Tomosynthesis, X-Ray 3D, Ophthalmic
            Tomography, Enhanced US Volume and similar keep their SOP Class with one
            frame per instance. Encapsulated (compressed) sources keep their transfer
            syntax frame by frame. Supports output as DICOM files or common image
            formats (PNG, JPEG, TIFF).

            --frame-numbers takes Frame numbers, numbered from 1 (PS3.3 C.7.6.16.1.2:
            "Frames are implicitly numbered starting from 1"). The 0-based --frames
            (index 0 is Frame number 1) is deprecated.

            Examples:
              # Extract all frames to DICOM files (Enhanced CT -> CT Image Storage)
              dicom-split multiframe.dcm --output frames/

              # Extract Frame numbers 2, 6 and 11-16
              dicom-split multiframe.dcm --frame-numbers 2,6,11-16 --output selected/

              # Keep the Enhanced SOP Class, one series per Stack ID
              dicom-split enhanced-mr.dcm --target same --split-by stack --output stacks/

              # Decode a JPEG 2000 multi-frame to native pixels while splitting
              dicom-split j2k-multiframe.dcm --pixel-handling decode --output native/

              # Split a Segmentation into Concatenation parts of 25 frames
              dicom-split seg.dcm --frames-per 25 --output parts/

              # Extract as PNG images with windowing
              dicom-split ct-multiframe.dcm \\
                --format png \\
                --apply-window \\
                --window-center 40 \\
                --window-width 400 \\
                --output images/

              # Batch processing with custom naming
              dicom-split studies/ \\
                --output split_studies/ \\
                --pattern "frame_{number:04d}_{modality}.dcm" \\
                --recursive
            """,
        version: "1.1.2"
    )
    
    @Argument(help: "Input DICOM file or directory")
    var input: String
    
    @Option(name: .long, help: "Output directory for extracted frames")
    var output: String = "."
    
    @Option(name: .long, help: "Frames to extract by Frame number, numbered from 1 (PS3.3 C.7.6.16.1.2), e.g. '1,3,5-10' (default: all)")
    var frameNumbers: String?

    @Option(name: .long, help: "deprecated: 0-based index; use --frame-numbers")
    var frames: String?
    
    @Option(name: .long, help: "Output format: dicom, png, jpeg, tiff (default: dicom)")
    var format: SplitOutputFormat = .dicom
    
    @Flag(name: .long, help: "Apply window/level settings to image output")
    var applyWindow: Bool = false
    
    @Option(name: .long, help: ArgumentHelp(SplitConsole.windowCenterHelp))
    var windowCenter: Double?
    
    @Option(name: .long, help: ArgumentHelp(SplitConsole.windowWidthHelp))
    var windowWidth: Double?
    
    @Option(name: .long, help: "Naming pattern for output files (variables: {number} / {number:04d} = 0-based frame index, {instance} = Instance Number, {stack} = Stack ID, {modality}, {series} = Series Number)")
    var pattern: String?

    @Option(name: .long, help: "SOP Class of the extracted frames: auto (the single-frame class when one exists, e.g. Enhanced CT Image Storage -> CT Image Storage), same (keep the source SOP Class), classic (require a single-frame class) (default: auto)")
    var target: SplitTargetPolicy = .auto

    @Option(name: .long, help: "Encapsulated (compressed) sources: preserve the transfer syntax per frame, or decode to Explicit VR Little Endian (default: preserve)")
    var pixelHandling: MultiframePixelHandling = .preserve

    @Option(name: .long, help: "Private Sequences in the Shared / Per-Frame Functional Groups Sequence items: flatten, keep, drop (default: flatten)")
    var privateGroups: PrivateFunctionalGroupPolicy = .flatten

    @Option(name: .long, help: "Instance Number (0020,0013) of the frames: frame (the 1-based Frame number), instack (In-Stack Position Number (0020,9057)), original (keep the source value) (default: frame)")
    var instanceNumber: SplitInstanceNumbering = .frame

    @Option(name: .long, help: "Write one series per: none, stack (Stack ID (0020,9056)), temporal (Temporal Position Index (0020,9128)) (default: none)")
    var splitBy: SplitSeriesGrouping = .none

    @Flag(name: .long, help: "Mint a new Series Instance UID (0020,000E) for the extracted frames")
    var newSeries: Bool = false

    @Option(name: .long, help: ArgumentHelp(SplitConsole.framesPerHelp))
    var framesPer: Int?

    @Flag(name: .long, help: "Generate random SOP/Series Instance UIDs instead of deriving them from the source (derived UIDs make the split reproducible and let frame references be rewritten)")
    var randomUids: Bool = false

    @Flag(name: .shortAndLong, help: "Recursively process directories")
    var recursive: Bool = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false

    mutating func validate() throws {
        // P-SPLIT-1: both spellings at once is refused with exit 1 (not a usage error).
        if frames != nil && frameNumbers != nil {
            throw SplitFrameSelectionConflict()
        }
    }

    /// The 0-based frame indices selected by --frame-numbers (1-based) or the deprecated
    /// --frames (0-based); nil selects every frame.
    func selectedFrameIndices() throws -> Set<Int>? {
        do {
            if let frameNumbers { return try SplitConsole.parseFrameNumberSelection(frameNumbers) }
            if let frames { return try SplitConsole.parseFrameSelection(frames) }
            return nil
        } catch let e as SplitConsole.FrameSelectionError {
            throw ValidationError(e.description)
        }
    }

    mutating func run() async throws {
        if frames != nil {
            fprintln(SplitConsole.framesDeprecatedLine)
        }
        // Validate input
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError(SplitConsole.inputNotFoundMessage(path: input))
        }

        // Create output directory
        try createOutputDirectory(output)

        var options = SplitOptions()
        options.target = target
        options.pixelHandling = pixelHandling
        options.privateGroups = privateGroups
        options.instanceNumbering = instanceNumber
        options.seriesGrouping = splitBy
        options.newSeries = newSeries
        options.framesPerInstance = framesPer
        options.deterministicUIDs = !randomUids
        if let framesPer, framesPer < 1 {
            throw ValidationError(SplitConsole.framesPerTooSmallMessage)
        }

        // Banner via the shared SplitConsole — the exact lines DICOMStudio's
        // Workshop emits (see Sources/DICOMKit/Splitting/SplitConsole.swift).
        if verbose {
            for line in SplitConsole.headerLines(
                input: input, output: output, format: format, frames: frames,
                applyWindow: applyWindow, windowCenter: windowCenter, windowWidth: windowWidth,
                options: options, frameNumbers: frameNumbers
            ) {
                fprintln(line)
            }
        }

        // Create splitter (shared DICOMKit engine; verbose output routed to stderr)
        let splitter = FrameSplitter(
            outputPath: output,
            format: format,
            applyWindow: applyWindow,
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            namingPattern: pattern,
            verbose: verbose,
            options: options,
            log: { fprintln($0) }
        )

        // Parse frame ranges through the shared parser (one copy of the grammar
        // and its error text for both surfaces).
        let frameIndices = try selectedFrameIndices()

        // Process files
        var isDirectory: ObjCBool = false
        let result: SplitResult
        if FileManager.default.fileExists(atPath: input, isDirectory: &isDirectory), isDirectory.boolValue {
            // Directory processing
            result = try await splitter.processDirectory(input, recursive: recursive, frameIndices: frameIndices)
        } else {
            // Single file processing
            var single = SplitResult()
            await splitter.processFile(input, frameIndices: frameIndices, into: &single)
            result = single
        }

        for line in SplitConsole.completionLines(result: result) { fprintln(line) }

        // Surface real extraction failures through the exit code so scripts can detect
        // them. Skips (non-DICOM or single-frame files) are not failures and keep exit 0.
        if result.failed > 0 {
            throw ExitCode.failure
        }
    }
    
    func createOutputDirectory(_ path: String) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw ValidationError(SplitConsole.outputNotDirectoryMessage(path: path))
            }
        } else {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }
}

// FrameSplitter + SplitError + SplitResult + SplitOutputFormat now live in the
// DICOMKit library (Sources/DICOMKit/Splitting/). ArgumentParser stays out of the
// library, so the CLI supplies the command-line conformance here.
extension SplitOutputFormat: ExpressibleByArgument {}
extension SplitTargetPolicy: ExpressibleByArgument {}
extension MultiframePixelHandling: ExpressibleByArgument {}
extension PrivateFunctionalGroupPolicy: ExpressibleByArgument {}
extension SplitInstanceNumbering: ExpressibleByArgument {}
extension SplitSeriesGrouping: ExpressibleByArgument {}

/// `--frames` and `--frame-numbers` given together. Not a `ValidationError`, so the command
/// exits 1 with this message.
struct SplitFrameSelectionConflict: LocalizedError, CustomStringConvertible {
    var description: String { SplitConsole.framesAndFrameNumbersConflictMessage }
    var errorDescription: String? { description }
}

/// Prints to stderr
private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}
