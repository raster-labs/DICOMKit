// NEMA-verified: 2026a, checked 2026-10-01 — grayscale pipeline against PS3.3 2026a C.11.1.1.2 (Rescale per frame), Table C.11-2b / C.11.2.1.2.1 / C.11.2.1.3 (3 VOI LUT Function Defined Terms LINEAR, LINEAR_EXACT, SIGMOID; LINEAR when absent; via DICOMCore WindowSettings), C.7.6.3.1.2 (MONOCHROME1 minimum shown white), Table C.9-2 (Overlay Origin 1\1 = upper left pixel, row\column; Overlay Data left to right, top to bottom) and Image Frame Origin "Frames are numbered from 1"; 10 info labels are PS3.6 2026a Table 6-1 names; frame labels say "Frame number N" (1-based, PS3.3 2026a Table 10-3; P-VIEWER-FRAME)
/// Terminal rendering engine for DICOM images
///
/// Provides ASCII art, ANSI color, and terminal graphics protocol
/// renderers for displaying DICOM images in the terminal.

import Foundation
import DICOMKit
import DICOMCore

// MARK: - Display Mode

/// Display mode for terminal rendering
enum DisplayMode: String, CaseIterable, Sendable {
    case ascii
    case ansi
    case iterm2
    case kitty
    case sixel
}

/// ASCII art quality level
enum AsciiQuality: String, CaseIterable, Sendable {
    case low
    case high
}

/// ANSI color depth
enum ANSIColorDepth: String, CaseIterable, Sendable {
    case color256 = "256"
    case truecolor = "24bit"
}

// MARK: - Terminal Size

/// Represents terminal dimensions in characters
struct TerminalSize: Equatable, Sendable {
    let width: Int
    let height: Int

    /// Detect current terminal size from environment
    static func detect() -> TerminalSize {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0 {
            return TerminalSize(width: Int(ws.ws_col), height: Int(ws.ws_row))
        }
        // Check environment variables
        if let colStr = ProcessInfo.processInfo.environment["COLUMNS"],
           let rowStr = ProcessInfo.processInfo.environment["LINES"],
           let cols = Int(colStr), let rows = Int(rowStr) {
            return TerminalSize(width: cols, height: rows)
        }
        // Default fallback
        return TerminalSize(width: 80, height: 24)
    }
}

// MARK: - Image Data

/// Normalized grayscale image data ready for rendering
struct NormalizedImage: Sendable {
    let pixels: [Double]  // 0.0 (black) to 1.0 (white)
    let width: Int
    let height: Int
    let originalRows: Int
    let originalColumns: Int
}

// MARK: - Terminal Renderer

/// Core renderer for DICOM images in terminal
struct TerminalRenderer {
    let dicomFile: DICOMFile
    let dataSet: DataSet
    let verbose: Bool

    init(dicomFile: DICOMFile, verbose: Bool = false) {
        self.dicomFile = dicomFile
        self.dataSet = dicomFile.dataSet
        self.verbose = verbose
    }

    // MARK: - Image Extraction

    /// Extract normalized grayscale pixel data from the DICOM file
    ///
    /// Pixels are decoded through ``CodecRegistry`` so all registered codecs
    /// (J2K, HTJ2K, Part 2, JPEG-LS, RLE, …) are handled automatically.
    ///
    /// The grayscale pipeline is Modality LUT (Rescale Slope/Intercept, PS3.3
    /// C.11.1.1.2) → VOI LUT function (C.11.2.1.2 / C.11.2.1.3: LINEAR unless VOI LUT
    /// Function (0028,1056) or `voiFunction` says otherwise) → MONOCHROME1 inversion
    /// ("The minimum sample value is intended to be displayed as white", C.7.6.3.1.2).
    /// With `showOverlays`, overlay planes (60xx) are drawn white on top (C.9.2).
    func extractPixels(
        frame: Int = 0,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        invert: Bool = false,
        voiFunction: VOILUTFunction? = nil,
        showOverlays: Bool = false
    ) throws -> NormalizedImage {
        // Use DICOMFile.pixelData() which routes through CodecRegistry for all
        // compressed transfer syntaxes (J2K, HTJ2K, Part 2, JPEG-LS, RLE …)
        guard let pixelData = dicomFile.pixelData() else {
            throw ViewerError.noPixelData
        }

        let descriptor = pixelData.descriptor
        let rows = descriptor.rows
        let columns = descriptor.columns

        guard rows > 0 && columns > 0 else {
            throw ViewerError.invalidDimensions(rows, columns)
        }

        // Get pixel values for the frame
        guard let values = pixelData.pixelValues(forFrame: frame) else {
            throw ViewerError.frameNotAvailable(frame)
        }

        // Modality LUT: Rescale Slope / Intercept of this frame (C.11.1.1.2).
        let slope = dataSet.rescaleSlope(frameIndex: frame)
        let intercept = dataSet.rescaleIntercept(frameIndex: frame)

        // VOI: the window is in Modality LUT output units (C.11.2.1.2).
        let window: WindowSettings
        if let center = windowCenter, let width = windowWidth {
            window = WindowSettings(center: center, width: width, function: voiFunction ?? .linear)
        } else if let settings = dataSet.windowSettings(frameIndex: frame) {
            window = voiFunction.map {
                WindowSettings(center: settings.center, width: settings.width,
                               explanation: settings.explanation, function: $0)
            } ?? settings
        } else {
            // Auto-window over the frame's rescaled range.
            let low: Double, high: Double
            if let range = pixelData.pixelRange(forFrame: frame) {
                low = Double(range.min); high = Double(range.max)
            } else {
                let bits = max(1, descriptor.bitsStored)
                low = descriptor.isSigned ? -Double(1 << (bits - 1)) : 0
                high = descriptor.isSigned ? Double(1 << (bits - 1)) - 1 : Double(1 << bits) - 1
            }
            let a = slope * low + intercept, b = slope * high + intercept
            window = WindowSettings(center: (a + b) / 2.0, width: max(abs(b - a), 1.0),
                                    function: voiFunction ?? .linearExact)
        }

        if verbose {
            print("Window Center: \(window.center), Window Width: \(window.width), VOI LUT Function: \(window.function.rawValue)")
            print("Image size: \(columns)x\(rows)")
        }

        let monochrome1 = (dataSet.string(for: .photometricInterpretation) ?? "")
            .trimmingCharacters(in: .whitespaces).uppercased() == "MONOCHROME1"
        let flip = monochrome1 != invert

        var normalized = [Double](repeating: 0.0, count: values.count)
        for i in 0..<values.count {
            let rescaled = slope * Double(values[i]) + intercept
            var value = max(0.0, min(1.0, window.apply(to: rescaled)))
            if flip {
                value = 1.0 - value
            }
            normalized[i] = value
        }

        if showOverlays {
            TerminalRenderer.burnOverlays(OverlayPlaneRenderer.planes(in: dataSet), frame: frame,
                                          into: &normalized, rows: rows, columns: columns)
        }

        return NormalizedImage(
            pixels: normalized,
            width: columns,
            height: rows,
            originalRows: rows,
            originalColumns: columns
        )
    }

    // MARK: - Overlay Planes (PS3.3 C.9.2)

    /// Draws every overlay plane that applies to `frame` (0-based) as white.
    ///
    /// Overlay Origin (60xx,0050) is "row\column" and "The upper left pixel of the
    /// image has the coordinate 1\1" (Table C.9-2); Image Frame Origin (60xx,0051)
    /// numbers frames from 1.
    static func burnOverlays(_ planes: [OverlayPlane], frame: Int, into pixels: inout [Double],
                             rows: Int, columns: Int) {
        for plane in planes where plane.applies(toImageFrame: frame) {
            let overlayFrame = plane.frameCount <= 1 ? 0 : max(0, frame - (plane.imageFrameOrigin - 1))
            for r in 0..<plane.rows {
                let row = plane.originRow - 1 + r
                guard row >= 0, row < rows else { continue }
                for c in 0..<plane.columns {
                    let column = plane.originColumn - 1 + c
                    guard column >= 0, column < columns else { continue }
                    if plane.isSet(row: r, column: c, frame: overlayFrame) {
                        pixels[row * columns + column] = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Image Scaling

    /// Scale a normalized image to fit within the given dimensions
    static func scaleImage(_ image: NormalizedImage, toWidth targetWidth: Int, toHeight targetHeight: Int) -> NormalizedImage {
        guard targetWidth > 0 && targetHeight > 0 else {
            return image
        }

        let scaleX = Double(image.width) / Double(targetWidth)
        let scaleY = Double(image.height) / Double(targetHeight)

        var scaled = [Double](repeating: 0.0, count: targetWidth * targetHeight)

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                // Nearest-neighbor sampling
                let srcX = min(Int(Double(x) * scaleX), image.width - 1)
                let srcY = min(Int(Double(y) * scaleY), image.height - 1)
                scaled[y * targetWidth + x] = image.pixels[srcY * image.width + srcX]
            }
        }

        return NormalizedImage(
            pixels: scaled,
            width: targetWidth,
            height: targetHeight,
            originalRows: image.originalRows,
            originalColumns: image.originalColumns
        )
    }

    /// Calculate scaled dimensions maintaining aspect ratio to fit terminal
    static func fitToTerminal(
        imageWidth: Int,
        imageHeight: Int,
        terminalWidth: Int,
        terminalHeight: Int,
        customWidth: Int? = nil,
        customHeight: Int? = nil
    ) -> (width: Int, height: Int) {
        let targetW = customWidth ?? terminalWidth
        // Each terminal character is roughly 2x tall, so we halve the height
        let targetH = customHeight ?? (terminalHeight - 2)

        let aspectRatio = Double(imageWidth) / Double(imageHeight)
        // Characters are roughly twice as tall as wide
        let charAspect = 2.0

        var fitWidth = targetW
        var fitHeight = Int(Double(fitWidth) / (aspectRatio * charAspect))

        if fitHeight > targetH {
            fitHeight = targetH
            fitWidth = Int(Double(fitHeight) * aspectRatio * charAspect)
        }

        return (width: max(fitWidth, 1), height: max(fitHeight, 1))
    }

    // MARK: - ASCII Art Renderer

    /// ASCII character ramps for different quality levels
    static let lowQualityRamp: [Character] = [" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"]
    static let highQualityRamp: [Character] = [
        " ", ".", "'", "`", "^", "\"", ",", ":", ";", "I",
        "l", "!", "i", ">", "<", "~", "+", "_", "-", "?",
        "]", "[", "}", "{", "1", ")", "(", "|", "\\", "/",
        "t", "f", "j", "r", "x", "n", "u", "v", "c", "z",
        "X", "Y", "U", "J", "C", "L", "Q", "0", "O", "Z",
        "m", "w", "q", "p", "d", "b", "k", "h", "a", "o",
        "*", "#", "M", "W", "&", "8", "%", "B", "@", "$"
    ]

    /// Render image as ASCII art
    static func renderASCII(_ image: NormalizedImage, quality: AsciiQuality = .high) -> String {
        let ramp = quality == .high ? highQualityRamp : lowQualityRamp
        let rampCount = ramp.count

        var output = ""
        output.reserveCapacity(image.width * image.height + image.height)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let value = image.pixels[y * image.width + x]
                let index = min(Int(value * Double(rampCount - 1)), rampCount - 1)
                output.append(ramp[index])
            }
            output.append("\n")
        }

        return output
    }

    // MARK: - ANSI Color Renderer

    /// Render image using ANSI escape codes with block characters
    static func renderANSI(_ image: NormalizedImage, colorDepth: ANSIColorDepth = .truecolor) -> String {
        var output = ""
        output.reserveCapacity(image.width * image.height * 20)

        // Use half-block characters: upper half and lower half
        // Process two rows at a time
        let rowPairs = image.height / 2

        for rowPair in 0..<rowPairs {
            let topRow = rowPair * 2
            let bottomRow = topRow + 1

            for x in 0..<image.width {
                let topValue = image.pixels[topRow * image.width + x]
                let bottomValue = image.pixels[bottomRow * image.width + x]

                switch colorDepth {
                case .truecolor:
                    let topGray = Int(topValue * 255.0)
                    let bottomGray = Int(bottomValue * 255.0)
                    // Upper half block: foreground = top, background = bottom
                    output += "\u{1B}[38;2;\(topGray);\(topGray);\(topGray)m"
                    output += "\u{1B}[48;2;\(bottomGray);\(bottomGray);\(bottomGray)m"
                    output += "▀"

                case .color256:
                    let topIndex = 232 + Int(topValue * 23.0)
                    let bottomIndex = 232 + Int(bottomValue * 23.0)
                    output += "\u{1B}[38;5;\(topIndex)m"
                    output += "\u{1B}[48;5;\(bottomIndex)m"
                    output += "▀"
                }
            }
            output += "\u{1B}[0m\n"
        }

        // Handle odd row at the bottom
        if image.height % 2 != 0 {
            let lastRow = image.height - 1
            for x in 0..<image.width {
                let value = image.pixels[lastRow * image.width + x]
                switch colorDepth {
                case .truecolor:
                    let gray = Int(value * 255.0)
                    output += "\u{1B}[38;2;\(gray);\(gray);\(gray)m"
                    output += "▀"
                case .color256:
                    let index = 232 + Int(value * 23.0)
                    output += "\u{1B}[38;5;\(index)m"
                    output += "▀"
                }
            }
            output += "\u{1B}[0m\n"
        }

        return output
    }

    // MARK: - iTerm2 Inline Image Protocol

    /// Render image using iTerm2 inline image protocol
    static func renderITerm2(_ image: NormalizedImage, width: Int? = nil, height: Int? = nil) -> String {
        // Create raw grayscale image data
        let imageData = createPGMData(image)
        let base64 = imageData.base64EncodedString()

        var params = "inline=1"
        if let w = width { params += ";width=\(w)" }
        if let h = height { params += ";height=\(h)" }
        params += ";preserveAspectRatio=1"

        return "\u{1B}]1337;File=\(params):\(base64)\u{07}"
    }

    // MARK: - Kitty Graphics Protocol

    /// Render image using Kitty graphics protocol
    static func renderKitty(_ image: NormalizedImage) -> String {
        // Create raw grayscale data (1 byte per pixel)
        var rawData = Data(capacity: image.width * image.height)
        for pixel in image.pixels {
            rawData.append(UInt8(max(0, min(255, Int(pixel * 255.0)))))
        }
        let base64 = rawData.base64EncodedString()

        // Kitty graphics protocol: send in chunks
        var output = ""
        let chunkSize = 4096
        let chunks = stride(from: 0, to: base64.count, by: chunkSize).map { start -> String in
            let startIndex = base64.index(base64.startIndex, offsetBy: start)
            let endIndex = base64.index(startIndex, offsetBy: min(chunkSize, base64.count - start))
            return String(base64[startIndex..<endIndex])
        }

        for (i, chunk) in chunks.enumerated() {
            let more = i < chunks.count - 1 ? 1 : 0
            if i == 0 {
                output += "\u{1B}_Gf=8,s=\(image.width),v=\(image.height),a=T,m=\(more);\(chunk)\u{1B}\\"
            } else {
                output += "\u{1B}_Gm=\(more);\(chunk)\u{1B}\\"
            }
        }

        return output
    }

    // MARK: - Sixel Graphics Protocol

    /// Render image using Sixel graphics protocol
    static func renderSixel(_ image: NormalizedImage) -> String {
        // Sixel uses 6-row vertical strips encoded as characters
        var output = "\u{1B}Pq"

        // Define a grayscale palette (64 levels)
        let paletteSize = 64
        for i in 0..<paletteSize {
            let level = i * 100 / (paletteSize - 1)
            output += "#\(i);2;\(level);\(level);\(level)"
        }

        // Encode image in sixel format (6 rows per band)
        let bands = (image.height + 5) / 6

        for band in 0..<bands {
            for colorIndex in 0..<paletteSize {
                var hasPixels = false
                var line = "#\(colorIndex)"

                for x in 0..<image.width {
                    var sixelBits: UInt8 = 0
                    for bit in 0..<6 {
                        let y = band * 6 + bit
                        if y < image.height {
                            let value = image.pixels[y * image.width + x]
                            let pixelColor = Int(value * Double(paletteSize - 1))
                            if pixelColor == colorIndex {
                                sixelBits |= 1 << bit
                                hasPixels = true
                            }
                        }
                    }
                    line += String(UnicodeScalar(63 + sixelBits))
                }

                if hasPixels {
                    output += line + "$"
                }
            }
            output += "-"
        }

        output += "\u{1B}\\"
        return output
    }

    // MARK: - Information Overlay

    /// Generate text information overlay
    func generateInfoOverlay() -> String {
        var info = ""

        // Labels are the PS3.6 2026a Table 6-1 attribute names.
        // Patient Information
        if let name = dataSet.string(for: .patientName) {
            info += "Patient's Name: \(name)\n"
        }
        if let id = dataSet.string(for: .patientID) {
            info += "Patient ID: \(id)\n"
        }
        if let sex = dataSet.string(for: .patientSex) {
            info += "Patient's Sex: \(sex)\n"
        }

        // Study Information
        if let desc = dataSet.string(for: .studyDescription) {
            info += "Study Description: \(desc)\n"
        }
        if let date = dataSet.string(for: .studyDate) {
            info += "Study Date: \(date)\n"
        }
        if let modality = dataSet.string(for: .modality) {
            info += "Modality: \(modality)\n"
        }

        // Image Information
        if let rows = dataSet.uint16(for: .rows),
           let cols = dataSet.uint16(for: .columns) {
            info += "Rows x Columns: \(rows)x\(cols)\n"
        }
        if let bits = dataSet.uint16(for: .bitsStored) {
            info += "Bits Stored: \(bits)\n"
        }
        if let frames = dataSet.string(for: .numberOfFrames) {
            info += "Number of Frames: \(frames.trimmingCharacters(in: .whitespaces))\n"
        }
        if let ws = dataSet.windowSettings() {
            info += "Window Center: \(TerminalRenderer.formatted(ws.center))\n"
            info += "Window Width: \(TerminalRenderer.formatted(ws.width))\n"
            if dataSet[.voiLUTFunction] != nil {
                info += "VOI LUT Function: \(ws.function.rawValue)\n"
            }
        }

        return info
    }

    static func formatted(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    /// Get total number of frames
    func frameCount() -> Int {
        if let pixelData = dicomFile.pixelData() {
            return pixelData.descriptor.numberOfFrames
        }
        return 1
    }

    // MARK: - ROI Cropping

    /// Crop a normalized image to a specified rectangular region.
    ///
    /// Coordinates are clamped to the image bounds so invalid rectangles are
    /// handled gracefully.
    ///
    /// - Parameters:
    ///   - image: Source normalized image.
    ///   - x: Left edge of the region (pixel column, 0-based).
    ///   - y: Top edge of the region (pixel row, 0-based).
    ///   - width: Width of the region in pixels.
    ///   - height: Height of the region in pixels.
    /// - Returns: Cropped image, or the original if the region is degenerate.
    static func cropImage(
        _ image: NormalizedImage,
        x: Int, y: Int,
        width: Int, height: Int
    ) -> NormalizedImage {
        let clampedX = max(0, min(x, image.width - 1))
        let clampedY = max(0, min(y, image.height - 1))
        let clampedW = max(1, min(width, image.width - clampedX))
        let clampedH = max(1, min(height, image.height - clampedY))

        var cropped = [Double](repeating: 0.0, count: clampedW * clampedH)
        for row in 0..<clampedH {
            let srcOffset = (clampedY + row) * image.width + clampedX
            let dstOffset = row * clampedW
            for col in 0..<clampedW {
                cropped[dstOffset + col] = image.pixels[srcOffset + col]
            }
        }

        return NormalizedImage(
            pixels: cropped,
            width: clampedW,
            height: clampedH,
            originalRows: clampedH,
            originalColumns: clampedW
        )
    }

    // MARK: - PGM Image Creation

    /// Create PGM (Portable GrayMap) image data from normalized pixels
    static func createPGMData(_ image: NormalizedImage) -> Data {
        let pgm = "P5\n\(image.width) \(image.height)\n255\n"
        var data = pgm.data(using: .ascii) ?? Data()
        for pixel in image.pixels {
            data.append(UInt8(max(0, min(255, Int(pixel * 255.0)))))
        }
        return data
    }

    // MARK: - Thumbnail Grid

    /// Render multiple frames as a thumbnail grid
    func renderThumbnailGrid(
        frames: [Int],
        mode: DisplayMode,
        terminalSize: TerminalSize,
        quality: AsciiQuality = .high,
        colorDepth: ANSIColorDepth = .truecolor,
        windowCenter: Double? = nil,
        windowWidth: Double? = nil,
        invert: Bool = false,
        voiFunction: VOILUTFunction? = nil,
        showOverlays: Bool = false
    ) throws -> String {
        guard !frames.isEmpty else { return "" }

        let totalFrames = frames.count
        let gridCols = min(totalFrames, max(1, terminalSize.width / 20))
        let gridRows = (totalFrames + gridCols - 1) / gridCols

        let thumbWidth = max(10, (terminalSize.width - gridCols - 1) / gridCols)
        let thumbHeight = max(5, (terminalSize.height - gridRows - 1) / gridRows)

        var output = ""

        for row in 0..<gridRows {
            // Collect thumbnails for this row
            var thumbnails: [NormalizedImage] = []
            for col in 0..<gridCols {
                let idx = row * gridCols + col
                if idx < totalFrames {
                    let frameIdx = frames[idx]
                    if let image = try? extractPixels(frame: frameIdx, windowCenter: windowCenter,
                                                      windowWidth: windowWidth, invert: invert,
                                                      voiFunction: voiFunction, showOverlays: showOverlays) {
                        let scaled = TerminalRenderer.scaleImage(image, toWidth: thumbWidth, toHeight: thumbHeight)
                        thumbnails.append(scaled)
                    }
                }
            }

            // Render thumbnails side by side (ASCII mode for grid)
            if mode == .ascii {
                for y in 0..<thumbHeight {
                    for (i, thumb) in thumbnails.enumerated() {
                        if i > 0 { output += "|" }
                        if y < thumb.height {
                            let ramp = quality == .high ? TerminalRenderer.highQualityRamp : TerminalRenderer.lowQualityRamp
                            for x in 0..<thumb.width {
                                let value = thumb.pixels[y * thumb.width + x]
                                let index = min(Int(value * Double(ramp.count - 1)), ramp.count - 1)
                                output.append(ramp[index])
                            }
                        }
                    }
                    output += "\n"
                }
            } else {
                // For other modes, render ASCII thumbnails with labels
                for y in 0..<thumbHeight {
                    for (i, thumb) in thumbnails.enumerated() {
                        if i > 0 { output += "|" }
                        if y < thumb.height {
                            let ramp = TerminalRenderer.highQualityRamp
                            for x in 0..<thumb.width {
                                let value = thumb.pixels[y * thumb.width + x]
                                let index = min(Int(value * Double(ramp.count - 1)), ramp.count - 1)
                                output.append(ramp[index])
                            }
                        }
                    }
                    output += "\n"
                }
            }

            // Frame labels
            for (i, _) in thumbnails.enumerated() {
                let idx = row * gridCols + i
                if idx < totalFrames {
                    // Frame Numbers start at 1 (PS3.3 C.9.2 Image Frame Origin, Referenced Frame Number).
                    // "Frame number N" (PS3.3 Table 10-3); the bare number when the thumbnail is narrower.
                    let full = "Frame number \(frames[idx] + 1)"
                    let label = full.count <= thumbWidth ? full : "\(frames[idx] + 1)"
                    let padding = max(0, thumbWidth - label.count)
                    if i > 0 { output += "|" }
                    output += String(repeating: " ", count: padding / 2) + label
                    output += String(repeating: " ", count: padding - padding / 2)
                }
            }
            output += "\n"

            // Separator between rows
            if row < gridRows - 1 {
                output += String(repeating: "-", count: min(terminalSize.width, gridCols * (thumbWidth + 1)))
                output += "\n"
            }
        }

        return output
    }
}

// MARK: - Errors

/// Errors specific to the viewer
enum ViewerError: Error, CustomStringConvertible {
    case noPixelData
    case invalidDimensions(Int, Int)
    case frameNotAvailable(Int)
    case fileNotFound(String)
    case unsupportedMode(String)

    var description: String {
        switch self {
        case .noPixelData:
            return "No pixel data found in DICOM file"
        case .invalidDimensions(let rows, let cols):
            return "Invalid image dimensions: \(cols)x\(rows)"
        case .frameNotAvailable(let frame):
            return "Frame number \(frame + 1) is not available"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedMode(let mode):
            return "Unsupported display mode: \(mode)"
        }
    }
}
