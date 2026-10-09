// NEMA-verified: 2026a, checked 2026-10-01 — 22 options (20 + new --voi-lut-function, --frame-number): window per PS3.3 2026a C.11.2.1.2.1 (LINEAR width >= 1; LINEAR_EXACT / SIGMOID width > 0, C.11.2.1.3.1/.2), VOI LUT Function values = the 3 Defined Terms of Table C.11-2b, frame numbering (--frame-number is 1-based, "The first Frame shall be denoted as Frame number 1", Table 10-3; --frame 0-based index deprecated with a stderr note, both given = exit 1, labels "Frame number N"; P-VIEWER-FRAME), --show-overlay draws 60xx overlay planes (C.9.2); display modes, sizes, ROI, JPIP are plumbing
import Foundation
import ArgumentParser
import DICOMKit
import DICOMCore
import DICOMDictionary

struct DICOMViewer: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dicom-viewer",
        abstract: "View DICOM images directly in the terminal",
        discussion: """
            Display DICOM images using ASCII art, ANSI colors, or terminal graphics
            protocols (iTerm2, Kitty, Sixel) for quick image inspection and triage.
            All registered codecs (J2K, HTJ2K, JPEG-LS, RLE …) are used automatically.
            
            Examples:
              dicom-viewer scan.dcm
              dicom-viewer scan.dcm --mode ascii --quality high
              dicom-viewer scan.dcm --mode ansi --color 24bit
              dicom-viewer ct.dcm --window-center -600 --window-width 1500
              dicom-viewer scan.dcm --show-info
              dicom-viewer series/*.dcm --thumbnail
              dicom-viewer j2k.dcm --reduce 2            # 1/4 resolution preview
              dicom-viewer ct.dcm --roi 100,50,256,256   # crop region x,y,w,h
              dicom-viewer volume.dcm --volume           # multi-frame / JP3D volume
              dicom-viewer --jpip "http://server/wado?..." # stream via JPIP
            """,
        version: "1.5.0"
    )

    @Argument(help: "Path(s) to DICOM file(s)")
    var filePaths: [String]

    @Option(name: .shortAndLong, help: "Display mode: ascii, ansi, iterm2, kitty, sixel")
    var mode: DisplayMode = .ascii

    @Option(name: .long, help: "ASCII art quality: low, high (default: high)")
    var quality: AsciiQuality = .high

    @Option(name: .long, help: "ANSI color depth: 256, 24bit (default: 24bit)")
    var color: ANSIColorDepth = .truecolor

    @Option(name: .long, help: "Window Center (level) for display, in Modality LUT output units (e.g. HU)")
    var windowCenter: Double?

    @Option(name: .long, help: "Window Width for display (>= 1 for LINEAR, > 0 for LINEAR_EXACT and SIGMOID; PS3.3 C.11.2.1.2.1)")
    var windowWidth: Double?

    @Option(name: .long, help: "VOI LUT Function (0028,1056) to apply the window with: LINEAR, LINEAR_EXACT, SIGMOID (default: the file's value, else LINEAR)")
    var voiLutFunction: String?

    @Option(name: .long, help: "Deprecated: 0-based index; use --frame-number (index 0 is Frame number 1)")
    var frame: Int?

    @Option(name: .long, help: "Frame number to display, 1-based (PS3.3 Table 10-3: the first Frame is Frame number 1); default 1")
    var frameNumber: Int?

    @Option(name: .long, help: "Output width in characters")
    var width: Int?

    @Option(name: .long, help: "Output height in characters")
    var height: Int?

    @Flag(name: .long, help: "Invert pixel values")
    var invert: Bool = false

    @Flag(name: .long, help: "Show patient and study information overlay")
    var showInfo: Bool = false

    @Flag(name: .long, help: "Draw overlay planes (60xx, PS3.3 C.9.2) and show a frame/size status line")
    var showOverlay: Bool = false

    @Flag(name: .long, help: "Display as thumbnail grid (for multiple files or frames)")
    var thumbnail: Bool = false

    @Option(name: .long, help: "Thumbnail grid size as WxH (e.g., 80x40)")
    var size: String?

    @Flag(name: .long, help: "Force parsing of files without DICM prefix")
    var force: Bool = false

    @Flag(name: .long, help: "Verbose output for debugging")
    var verbose: Bool = false

    // MARK: - J2KSwift / Phase 7 options

    @Option(name: .long,
            help: "Resolution reduce factor n: decode at 1/2^n spatial resolution (0 = full).")
    var reduce: Int = 0

    @Option(name: .long,
            help: "Region of interest as \"x,y,width,height\" (pixel coordinates, 0-based).")
    var roi: String?

    @Flag(name: .long,
          help: "Volume / multi-frame mode: display all frames as a thumbnail filmstrip.")
    var volume: Bool = false

    @Option(name: .long,
            help: "Fetch and display image from a JPIP server URL (currently unavailable: upstream JPIP retrieval is unimplemented — see RESEARCH_ADOPTION_PLAN.md F1).")
    var jpip: String?

    mutating func validate() throws {
        // When --jpip is provided a local file path is optional
        guard !filePaths.isEmpty || jpip != nil else {
            throw ValidationError("At least one DICOM file path or --jpip URL is required")
        }

        for path in filePaths {
            guard FileManager.default.fileExists(atPath: path) else {
                throw ValidationError("File not found: \(path)")
            }
        }

        if windowCenter != nil && windowWidth == nil {
            throw ValidationError("--window-width must be provided when --window-center is set")
        }

        if windowWidth != nil && windowCenter == nil {
            throw ValidationError("--window-center must be provided when --window-width is set")
        }

        if let frame, frame < 0 {
            throw ValidationError("--frame (deprecated 0-based index) must be non-negative")
        }

        if let number = frameNumber, number < 1 {
            throw ValidationError("--frame-number must be >= 1 (the first Frame is Frame number 1)")
        }

        let function = try parsedVOIFunction()
        if let width = windowWidth {
            // PS3.3 C.11.2.1.2.1 (LINEAR): "shall always be greater than or equal to 1";
            // C.11.2.1.3.1 (SIGMOID) / C.11.2.1.3.2 (LINEAR_EXACT): "greater than 0".
            if (function ?? .linear) == .linear {
                guard width >= 1 else {
                    throw ValidationError("--window-width must be >= 1 for LINEAR (PS3.3 C.11.2.1.2.1)")
                }
            } else {
                guard width > 0 else {
                    throw ValidationError("--window-width must be > 0 for \(function!.rawValue) (PS3.3 C.11.2.1.3)")
                }
            }
        }

        if let w = width, w < 1 {
            throw ValidationError("Width must be at least 1")
        }
        if let h = height, h < 1 {
            throw ValidationError("Height must be at least 1")
        }

        if reduce < 0 {
            throw ValidationError("--reduce must be non-negative")
        }

        // Parse size option
        if let sizeStr = size {
            let parts = sizeStr.lowercased().split(separator: "x")
            guard parts.count == 2,
                  let w = Int(parts[0]), w > 0,
                  let h = Int(parts[1]), h > 0 else {
                throw ValidationError("Size must be in format WxH (e.g., 80x40)")
            }
        }

        // Validate ROI format
        if let roiStr = roi {
            let parts = roiStr.split(separator: ",")
            guard parts.count == 4,
                  parts.allSatisfy({ Int($0) != nil }) else {
                throw ValidationError("--roi must be in format \"x,y,width,height\" with integer values")
            }
        }
    }

    /// --voi-lut-function as a PS3.3 Table C.11-2b Defined Term (case-insensitive).
    func parsedVOIFunction() throws -> VOILUTFunction? {
        guard let text = voiLutFunction else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "-", with: "_")
        guard let function = VOILUTFunction(rawValue: normalized) else {
            throw ValidationError("--voi-lut-function must be LINEAR, LINEAR_EXACT or SIGMOID (PS3.3 C.11.2.1.3)")
        }
        return function
    }

    /// 0-based frame index selected by --frame-number (1-based) or the deprecated --frame (0-based).
    var frameIndex: Int { frameNumber.map { $0 - 1 } ?? frame ?? 0 }

    /// Stderr note when the deprecated --frame is used.
    var frameDeprecationNote: String? {
        frame.map { "Note: --frame is deprecated (0-based index); use --frame-number \($0 + 1)" }
    }

    mutating func run() throws {
        if frame != nil && frameNumber != nil {
            FileHandle.standardError.write(Data(
                "Error: --frame (deprecated 0-based index) and --frame-number both given; use --frame-number only\n".utf8))
            throw ExitCode.failure
        }
        if let note = frameDeprecationNote {
            FileHandle.standardError.write(Data((note + "\n").utf8))
        }
        // JPIP remote mode: no local file required
        if let jpipURLStr = jpip {
            try renderJPIP(urlString: jpipURLStr)
            return
        }

        if volume {
            try renderVolume()
        } else if thumbnail && filePaths.count > 1 {
            try renderMultiFileThumbnails()
        } else if thumbnail {
            try renderFrameThumbnails()
        } else {
            try renderSingleImage()
        }
    }

    // MARK: - Single Image Rendering

    private func renderSingleImage() throws {
        let path = filePaths[0]

        if verbose {
            print("Reading DICOM file: \(path)")
        }

        let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
        let dicomFile = try DICOMFile.read(from: fileData, force: force)
        let renderer = TerminalRenderer(dicomFile: dicomFile, verbose: verbose)

        // Show info overlay
        if showInfo {
            let info = renderer.generateInfoOverlay()
            print(info)
            print(String(repeating: "─", count: 40))
        }

        // Extract and render
        let totalFrames = renderer.frameCount()
        guard frameIndex < totalFrames else {
            throw ValidationError("Frame number \(frameIndex + 1) does not exist; Number of Frames is \(totalFrames)")
        }
        var image = try renderer.extractPixels(
            frame: frameIndex,
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            invert: invert,
            voiFunction: try parsedVOIFunction(),
            showOverlays: showOverlay
        )

        // Apply resolution reduce (post-decode downscale by 2^n)
        if reduce > 0 {
            let factor = 1 << reduce
            let reducedW = max(1, image.width / factor)
            let reducedH = max(1, image.height / factor)
            image = TerminalRenderer.scaleImage(image, toWidth: reducedW, toHeight: reducedH)
            if verbose {
                print("Reduced by factor \(factor): \(reducedW)x\(reducedH)")
            }
        }

        // Apply ROI crop
        if let roiStr = roi {
            let parts = roiStr.split(separator: ",").compactMap { Int($0) }
            if parts.count == 4 {
                image = TerminalRenderer.cropImage(
                    image,
                    x: parts[0], y: parts[1],
                    width: parts[2], height: parts[3]
                )
                if verbose {
                    print("Cropped to ROI (\(parts[0]),\(parts[1])) \(image.width)x\(image.height)")
                }
            }
        }

        let termSize = TerminalSize.detect()
        let fitSize = TerminalRenderer.fitToTerminal(
            imageWidth: image.width,
            imageHeight: image.height,
            terminalWidth: termSize.width,
            terminalHeight: termSize.height,
            customWidth: width,
            customHeight: height
        )

        let scaled = TerminalRenderer.scaleImage(image, toWidth: fitSize.width, toHeight: fitSize.height)

        if verbose {
            print("Terminal: \(termSize.width)x\(termSize.height)")
            print("Scaled to: \(fitSize.width)x\(fitSize.height)")
        }

        let output: String
        switch mode {
        case .ascii:
            output = TerminalRenderer.renderASCII(scaled, quality: quality)
        case .ansi:
            output = TerminalRenderer.renderANSI(scaled, colorDepth: color)
        case .iterm2:
            output = TerminalRenderer.renderITerm2(image, width: width, height: height)
        case .kitty:
            output = TerminalRenderer.renderKitty(image)
        case .sixel:
            output = TerminalRenderer.renderSixel(scaled)
        }

        print(output, terminator: "")

        // Show overlay info at bottom
        if showOverlay {
            print("\u{1B}[0m") // Reset colors
            print("[\(path)] Frame number \(frameIndex + 1) of \(totalFrames) | \(image.originalColumns)x\(image.originalRows)")
        }
    }

    // MARK: - Thumbnail Grid Rendering

    private func renderFrameThumbnails() throws {
        let path = filePaths[0]
        let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
        let dicomFile = try DICOMFile.read(from: fileData, force: force)
        let renderer = TerminalRenderer(dicomFile: dicomFile, verbose: verbose)

        let totalFrames = renderer.frameCount()
        let frameIndices = Array(0..<totalFrames)

        if verbose {
            print("Rendering \(totalFrames) frames as thumbnails")
        }

        let termSize = parseTerminalSize()

        let output = try renderer.renderThumbnailGrid(
            frames: frameIndices,
            mode: mode,
            terminalSize: termSize,
            quality: quality,
            colorDepth: color,
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            invert: invert,
            voiFunction: try parsedVOIFunction(),
            showOverlays: showOverlay
        )

        print(output, terminator: "")
    }

    private func renderMultiFileThumbnails() throws {
        let termSize = parseTerminalSize()
        let totalFiles = filePaths.count
        let gridCols = min(totalFiles, max(1, termSize.width / 20))
        let thumbWidth = max(10, (termSize.width - gridCols - 1) / gridCols)
        let thumbHeight = max(5, (termSize.height - 2) / ((totalFiles + gridCols - 1) / gridCols))

        if verbose {
            print("Rendering \(totalFiles) files as thumbnails (\(gridCols) columns)")
        }

        var output = ""
        var rowThumbnails: [(NormalizedImage, String)] = []

        for (i, path) in filePaths.enumerated() {
            do {
                let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
                let dicomFile = try DICOMFile.read(from: fileData, force: force)
                let renderer = TerminalRenderer(dicomFile: dicomFile, verbose: false)
                let image = try renderer.extractPixels(
                    windowCenter: windowCenter,
                    windowWidth: windowWidth,
                    invert: invert,
                    voiFunction: try parsedVOIFunction(),
                    showOverlays: showOverlay
                )
                let scaled = TerminalRenderer.scaleImage(image, toWidth: thumbWidth, toHeight: thumbHeight)
                let filename = URL(fileURLWithPath: path).lastPathComponent
                rowThumbnails.append((scaled, filename))
            } catch {
                if verbose {
                    print("Warning: Could not render \(path): \(error)")
                }
            }

            // Render row when full or at end
            if rowThumbnails.count == gridCols || i == filePaths.count - 1 {
                // Render thumbnails side by side
                let ramp = quality == .high ? TerminalRenderer.highQualityRamp : TerminalRenderer.lowQualityRamp
                for y in 0..<thumbHeight {
                    for (j, (thumb, _)) in rowThumbnails.enumerated() {
                        if j > 0 { output += " " }
                        if y < thumb.height {
                            for x in 0..<thumb.width {
                                let value = thumb.pixels[y * thumb.width + x]
                                let index = min(Int(value * Double(ramp.count - 1)), ramp.count - 1)
                                output.append(ramp[index])
                            }
                        }
                    }
                    output += "\n"
                }

                // Labels
                for (j, (_, name)) in rowThumbnails.enumerated() {
                    if j > 0 { output += " " }
                    let truncated = name.count > thumbWidth ? String(name.prefix(thumbWidth - 3)) + "..." : name
                    let padding = max(0, thumbWidth - truncated.count)
                    output += String(repeating: " ", count: padding / 2) + truncated
                    output += String(repeating: " ", count: padding - padding / 2)
                }
                output += "\n\n"

                rowThumbnails.removeAll()
            }
        }

        print(output, terminator: "")
    }

    // MARK: - Helpers

    private func parseTerminalSize() -> TerminalSize {
        if let sizeStr = size {
            let parts = sizeStr.lowercased().split(separator: "x")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                return TerminalSize(width: w, height: h)
            }
        }
        return TerminalSize.detect()
    }

    // MARK: - Volume / Multi-frame Rendering

    /// Display all frames of a multi-frame (or JP3D) DICOM file as a thumbnail filmstrip.
    private func renderVolume() throws {
        let path = filePaths[0]

        if verbose {
            print("Volume mode: \(path)")
        }

        let fileData = try Data(contentsOf: URL(fileURLWithPath: path))
        let dicomFile = try DICOMFile.read(from: fileData, force: force)
        let renderer = TerminalRenderer(dicomFile: dicomFile, verbose: verbose)

        let totalFrames = renderer.frameCount()
        if totalFrames < 1 {
            print("No frames found in \(path)")
            return
        }

        if showInfo {
            print(renderer.generateInfoOverlay())
            print(String(repeating: "─", count: 40))
        }

        print("Volume: \(totalFrames) frames — \(path)")

        let termSize = parseTerminalSize()
        let frameIndices = Array(0..<totalFrames)

        let output = try renderer.renderThumbnailGrid(
            frames: frameIndices,
            mode: mode,
            terminalSize: termSize,
            quality: quality,
            colorDepth: color,
            windowCenter: windowCenter,
            windowWidth: windowWidth,
            invert: invert,
            voiFunction: try parsedVOIFunction(),
            showOverlays: showOverlay
        )
        print(output, terminator: "")
    }

    // MARK: - JPIP Remote Rendering

    /// Fetch an image from a JPIP server URL and render it.
    private func renderJPIP(urlString: String) throws {
        guard let jpipURL = URL(string: urlString) else {
            fputs("Error: invalid JPIP URL: \(urlString)\n", stderr)
            throw ExitCode.failure
        }

        // JPIP retrieval is unavailable — DICOMJPIPClient's fetch methods are marked
        // @available(*, unavailable) because every request path in the pinned upstream
        // J2KSwift JPIP module (11.0.2) throws notImplemented. The rendering pipeline
        // that consumed the fetched image is recoverable from git history at de67c39
        // and should be restored when upstream lands. F1 in RESEARCH_ADOPTION_PLAN.md.
        fputs("""
            Error: JPIP rendering is not available in this build.

            Target: \(jpipURL.absoluteString)

            Retrieving pixel data over JPIP requires an implemented request path; the
            pinned J2KSwift JPIP module (11.0.2) has none. Render a local DICOM file
            instead, or use dicom-wado / dicom-retrieve for remote sources.

            """, stderr)
        throw ExitCode.failure
    }
}

// MARK: - ExpressibleByArgument conformances

extension DisplayMode: ExpressibleByArgument {}
extension AsciiQuality: ExpressibleByArgument {}
extension ANSIColorDepth: ExpressibleByArgument {}

DICOMViewer.main()
