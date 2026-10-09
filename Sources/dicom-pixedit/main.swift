// NEMA-verified: 2026a, checked 2026-10-01 — 10 options: --fill-value outside the Bits Stored / Pixel Representation range (PS3.3 2026a C.7.6.3.1) and --window-width < 1 (C.11.2.1.2) refused with exit 1 (P-PIXEDIT-RANGE), --window-center/--window-width in Modality LUT output units (C.11.2.1.2, Rescale Slope/Intercept C.11.1), output marked as a Derived Image (C.7.6.1.1.2, Table C.12-10; done by the DICOMKit PixelEditor engine, D169-D174); --output/--verbose/<input> are plumbing
import Foundation
import ArgumentParser
import DICOMCore
import DICOMKit
import DICOMDictionary

@available(macOS 10.15, *)
struct DICOMPixedit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-pixedit",
        abstract: "Edit pixel data in DICOM files",
        discussion: """
            Provides pixel data manipulation tools for DICOM images: masking
            rectangular regions (e.g. burned-in annotation), cropping, baking a
            window into the stored values, and inverting stored values.

            The output is a Derived Image (PS3.3 C.7.6.1.1.2): it gets a new SOP
            Instance UID, Image Type (0008,0008) Value 1 DERIVED, a Derivation
            Description (0008,2111) and a Source Image Sequence (0008,2112) item
            referencing the input. Burned In Annotation (0028,0301) and Lossy
            Image Compression (0028,2110) are left as they are. Operations run in
            the order mask, crop, window, invert; regions are in the input's
            pixel coordinates (0-based column, row).
            
            Examples:
              # Mask a region (e.g., burned-in text)
              dicom-pixedit file.dcm --output masked.dcm --mask-region 0,0,200,50
              
              # Mask with specific fill value
              dicom-pixedit file.dcm --output masked.dcm --mask-region 0,0,200,50 --fill-value 0
              
              # Crop to region of interest
              dicom-pixedit file.dcm --output cropped.dcm --crop 100,100,400,400
              
              # Adjust window/level permanently (bake into pixel data)
              dicom-pixedit ct.dcm --output windowed.dcm --window-center 40 --window-width 400 --apply-window
              
              # Invert pixel values
              dicom-pixedit file.dcm --output inverted.dcm --invert
            """,
        version: "1.3.0"
    )
    
    @Argument(help: "Input DICOM file path")
    var input: String
    
    @Option(name: .long, help: "Output DICOM file path")
    var output: String
    
    @Option(name: .long, help: "Mask region x,y,width,height (0-based column, row) - sets every sample in it to --fill-value")
    var maskRegion: String?
    
    @Option(name: .long, help: "Stored value for masked samples (default: 0); must lie in the range of Bits Stored (0028,0101) and Pixel Representation (0028,0103) (PS3.3 C.7.6.3.1), else exit 1")
    var fillValue: Int?
    
    @Option(name: .long, help: "Crop region x,y,width,height (0-based column, row); Rows/Columns and Image Position (Patient) are updated")
    var crop: String?
    
    @Option(name: .long, help: "Window Center (0028,1050) for --apply-window, in Modality LUT output units (e.g. HU for CT; PS3.3 C.11.2.1.2)")
    var windowCenter: Double?
    
    @Option(name: .long, help: "Window Width (0028,1051) for --apply-window, in Modality LUT output units; at least 1 (PS3.3 C.11.2.1.2), else exit 1")
    var windowWidth: Double?
    
    @Flag(name: .long, help: "Bake the window (PS3.3 C.11.2.1.2 linear function) into the stored pixel values")
    var applyWindow: Bool = false
    
    @Flag(name: .long, help: "Invert stored pixel values across the Bits Stored range")
    var invert: Bool = false
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    mutating func run() throws {
        // Validate input file exists
        guard FileManager.default.fileExists(atPath: input) else {
            throw ValidationError("Input file not found: \(input)")
        }
        
        // Build operations list. PixelEditor + PixelOperation + PixelEditError now
        // live in the DICOMKit library; verbose output is routed to stderr here.
        let inputData = try Data(contentsOf: URL(fileURLWithPath: input))
        let source = try DICOMFile.read(from: inputData)
        var operations: [PixelOperation] = []

        let editor = PixelEditor(verbose: verbose, log: { fprintln($0) })
        
        if let maskRegionStr = maskRegion {
            let region = try editor.parseRegion(maskRegionStr)
            let fill = fillValue ?? 0
            if let refusal = DICOMKit.PixelEditInputChecks.fillValueViolation(fill, range: DICOMKit.PixelEditInputChecks.storedRange(of: source.dataSet)) {
                throw ValidationError(refusal)
            }
            operations.append(.mask(x: region.x, y: region.y, width: region.width, height: region.height, fillValue: fill))
        }
        
        if let cropStr = crop {
            let region = try editor.parseRegion(cropStr)
            operations.append(.crop(x: region.x, y: region.y, width: region.width, height: region.height))
        }
        
        if applyWindow {
            guard let center = windowCenter, let requestedWidth = windowWidth else {
                throw ValidationError("--apply-window requires both --window-center and --window-width")
            }
            let width = requestedWidth
            if let refusal = DICOMKit.PixelEditInputChecks.windowWidthViolation(width) {
                throw ValidationError(refusal)
            }
            // Modality LUT output units (C.11.2.1.2); the engine applies Rescale / LUT.
            operations.append(.windowLevel(center: center, width: width))
        }
        
        if invert {
            operations.append(.invert)
        }
        
        guard !operations.isEmpty else {
            throw ValidationError("No operations specified. Use --mask-region, --crop, --apply-window, or --invert")
        }
        
        if verbose {
            for line in PixelEditConsole.headerLines(input: input, output: output, operationCount: operations.count) {
                fprintln(line)
            }
        }

        // The engine writes a Derived Image (new SOP Instance UID, Image Type DERIVED,
        // Derivation Description "dicom-pixedit: …", Source Image Sequence).
        let (edited, _) = try editor.processData(
            inputData, operations: operations,
            derivation: PixelEditDerivation(descriptionPrefix: "dicom-pixedit"))
        try edited.write(to: URL(fileURLWithPath: output))
        if verbose {
            fprintln(PixelEditConsole.writtenLine(path: URL(fileURLWithPath: output).path))
        }

        if verbose {
            fprintln(PixelEditConsole.doneLine())
        }
    }
}

struct ValidationError: Error, LocalizedError {
    let message: String
    
    init(_ message: String) {
        self.message = message
    }
    
    var errorDescription: String? {
        message
    }
}

private func fprintln(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8) ?? Data())
}

DICOMPixedit.main()
