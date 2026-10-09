// NEMA-verified: 2026a, checked 2026-09-29 — the 13 tags named in ComposedFilmInfo (2000,xxxx; 2010,xxxx; 2050,0020) checked against PS3.6 2026a Table 6-1 names (Scripts/diff_printkit.py); DensityMapping gsdf per PS3.14 7.2/7.3
//
// ComposedFilm.swift
// DICOMPrintKit
//
// The product of ``FilmComposer``: one rasterized film sheet plus the metadata
// a viewer, a sink, or a debugging inspector needs.
//
// Held as raw bytes rather than a `CGImage` so the value stays `Sendable` and
// hashable — the composer's tests assert on a bitmap hash, mirroring the
// decoded-pixel-hash approach used by the compression parity suite.
//

import Foundation
import DICOMNetwork

#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Density mapping

/// How DICOM optical density is interpreted when the film is rendered to a
/// screen or to paper.
///
/// Film density has no direct analogue on either, so the choice is explicit
/// rather than a hidden default (see the plan's risk 1).
public enum DensityMapping: String, Sendable, Hashable, CaseIterable, Codable {
    /// Render P-Values straight: MONOCHROME2 stays as-is, Min/Max Density only
    /// clamp the black and white points. The sensible default for paper and for
    /// an on-screen emulator.
    case paperDirect = "PAPER"

    /// Emulate a transmissive film on a lightbox: the rendered sheet is
    /// inverted relative to `paperDirect`, so dense areas read as dark.
    case filmEmulation = "FILM"

    /// Calibrated: draw what a printer conforming to PS3.14 produces. Each
    /// P-Value is laid down at the density the Grayscale Standard Display
    /// Function gives it between Min and Max Density (PS3.14 7.2 for film,
    /// 7.3 for PAPER), LIN OD and numeric Border/Empty densities are taken as
    /// densities, and the sheet's luminance under PS3.14's typical viewing
    /// conditions is encoded for the screen.
    case gsdf = "GSDF"

    public var displayName: String {
        switch self {
        case .paperDirect: return "Paper (direct)"
        case .filmEmulation: return "Film emulation"
        case .gsdf: return "Calibrated (PS3.14 GSDF)"
        }
    }
}

// MARK: - Film info

/// Everything about a composed film except its pixels.
///
/// Doubles as the "film attributes" inspector payload — the reason an emulator
/// beats a real printer for SCU developers.
public struct ComposedFilmInfo: Sendable, Hashable, Codable {
    /// Print Job SOP Instance UID the SCP allocated.
    public let printJobUID: String
    /// Film Session SOP Instance UID.
    public let filmSessionUID: String
    /// Film Box SOP Instance UID.
    public let filmBoxUID: String
    /// The calling AE that sent the job.
    public let callingAETitle: String
    /// When the film was received.
    public let receivedAt: Date

    /// Film Size ID (2010,0050).
    public let filmSize: String
    /// Film Orientation (2010,0040).
    public let filmOrientation: String
    /// Image Display Format (2010,0010) as received.
    public let imageDisplayFormat: String
    /// Rows in the layout grid.
    public let rows: Int
    /// Columns in the layout grid.
    public let columns: Int
    /// Medium Type (2000,0030).
    public let mediumType: String
    /// Number of Copies (2000,0010).
    public let numberOfCopies: Int
    /// Film Session Label (2000,0050).
    public let filmSessionLabel: String?
    /// Magnification Type (2010,0060).
    public let magnificationType: String
    /// Border Density (2010,0100).
    public let borderDensity: String
    /// Empty Image Density (2010,0110).
    public let emptyImageDensity: String
    /// Trim (2010,0140).
    public let trim: String
    /// Min Density (2010,0120), when set.
    public let minDensity: UInt16?
    /// Max Density (2010,0130), when set.
    public let maxDensity: UInt16?
    /// Presentation LUT Shape (2050,0020), when a LUT was referenced.
    public let presentationLUTShape: String?
    /// Annotations placed on the film, "position: text".
    public let annotations: [String]

    /// Sheet width in millimetres.
    public let sheetWidthMillimeters: Double
    /// Sheet height in millimetres.
    public let sheetHeightMillimeters: Double
    /// Rasterization resolution.
    public let dpi: Double
    /// Density interpretation used to render.
    public let densityMapping: DensityMapping
    /// Image boxes that carried pixels.
    public let filledImageBoxCount: Int
    /// Image boxes the layout provides.
    public let imageBoxCount: Int
    /// Boxes the composer could not place, with the reason (e.g. FAIL behavior).
    public let skippedImageBoxes: [String]

    public init(
        printJobUID: String, filmSessionUID: String, filmBoxUID: String,
        callingAETitle: String, receivedAt: Date,
        filmSize: String, filmOrientation: String, imageDisplayFormat: String,
        rows: Int, columns: Int, mediumType: String, numberOfCopies: Int,
        filmSessionLabel: String?, magnificationType: String,
        borderDensity: String, emptyImageDensity: String, trim: String,
        minDensity: UInt16?, maxDensity: UInt16?, presentationLUTShape: String?,
        annotations: [String], sheetWidthMillimeters: Double, sheetHeightMillimeters: Double,
        dpi: Double, densityMapping: DensityMapping,
        filledImageBoxCount: Int, imageBoxCount: Int, skippedImageBoxes: [String]
    ) {
        self.printJobUID = printJobUID
        self.filmSessionUID = filmSessionUID
        self.filmBoxUID = filmBoxUID
        self.callingAETitle = callingAETitle
        self.receivedAt = receivedAt
        self.filmSize = filmSize
        self.filmOrientation = filmOrientation
        self.imageDisplayFormat = imageDisplayFormat
        self.rows = rows
        self.columns = columns
        self.mediumType = mediumType
        self.numberOfCopies = numberOfCopies
        self.filmSessionLabel = filmSessionLabel
        self.magnificationType = magnificationType
        self.borderDensity = borderDensity
        self.emptyImageDensity = emptyImageDensity
        self.trim = trim
        self.minDensity = minDensity
        self.maxDensity = maxDensity
        self.presentationLUTShape = presentationLUTShape
        self.annotations = annotations
        self.sheetWidthMillimeters = sheetWidthMillimeters
        self.sheetHeightMillimeters = sheetHeightMillimeters
        self.dpi = dpi
        self.densityMapping = densityMapping
        self.filledImageBoxCount = filledImageBoxCount
        self.imageBoxCount = imageBoxCount
        self.skippedImageBoxes = skippedImageBoxes
    }

    /// A one-line summary for logs and job lists.
    public var summary: String {
        "\(filmSize) \(filmOrientation.lowercased()) \(rows)×\(columns), "
            + "\(filledImageBoxCount)/\(imageBoxCount) images, from \(callingAETitle)"
    }

    /// The attributes as pretty-printed JSON (the UI's "Copy attributes" action).
    public func jsonRepresentation() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

// MARK: - Composed film

/// A rasterized film sheet.
public struct ComposedFilm: Sendable, Hashable {
    /// Film and job metadata.
    public let info: ComposedFilmInfo

    /// Sheet width in pixels.
    public let width: Int

    /// Sheet height in pixels.
    public let height: Int

    /// Samples per pixel: 1 for grayscale films, 3 for color.
    public let samplesPerPixel: Int

    /// 8-bit, row-major, tightly packed pixels (`width * height * samplesPerPixel` bytes).
    public let pixels: Data

    public init(info: ComposedFilmInfo, width: Int, height: Int, samplesPerPixel: Int, pixels: Data) {
        self.info = info
        self.width = width
        self.height = height
        self.samplesPerPixel = samplesPerPixel
        self.pixels = pixels
    }

    /// Bytes per pixel row.
    public var bytesPerRow: Int { width * samplesPerPixel }

    /// Whether this film was composed in color.
    public var isColor: Bool { samplesPerPixel == 3 }

    /// A stable fingerprint of the bitmap, for golden tests and de-duplication.
    ///
    /// FNV-1a over the pixel bytes: cheap, dependency-free, and stable across
    /// runs and platforms (unlike `Data.hashValue`, which is seeded per process).
    public var pixelFingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        pixels.withUnsafeBytes { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01b3
            }
        }
        return String(format: "%016llx", hash)
    }

    #if canImport(CoreGraphics)
    /// Builds a `CGImage` for display, PDF, or file output.
    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0, pixels.count >= bytesPerRow * height else { return nil }
        let colorSpace = samplesPerPixel == 3
            ? CGColorSpaceCreateDeviceRGB()
            : CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8 * samplesPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)
    }

    /// A downsampled copy for on-screen display.
    ///
    /// A 14×17 in film at 300 DPI is ~4200×5100 px; keeping every received film
    /// at full resolution in a viewer's scrollback balloons memory fast, so the
    /// screen path holds these instead (plan risk 2).
    public func downsampled(maxDimension: Int) -> ComposedFilm {
        let longest = max(width, height)
        guard longest > maxDimension, maxDimension > 0, let source = makeCGImage() else { return self }
        let scale = Double(maxDimension) / Double(longest)
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))

        // As in `FilmComposer`: a bitmap context cannot be 24 bpp RGB, so colour
        // is drawn as RGBX and compacted back to three samples per pixel.
        let contextSamples = samplesPerPixel == 3 ? 4 : 1
        let contextBytesPerRow = targetWidth * contextSamples
        var scratch = Data(count: contextBytesPerRow * targetHeight)

        let drawn: Bool = scratch.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: targetWidth, height: targetHeight,
                    bitsPerComponent: 8, bytesPerRow: contextBytesPerRow,
                    space: samplesPerPixel == 3
                        ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: samplesPerPixel == 3
                        ? CGImageAlphaInfo.noneSkipLast.rawValue
                        : CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard drawn else { return self }

        var pixels = scratch
        if samplesPerPixel == 3 {
            var compacted = Data(count: targetWidth * targetHeight * 3)
            scratch.withUnsafeBytes { input in
                compacted.withUnsafeMutableBytes { result in
                    guard let src = input.bindMemory(to: UInt8.self).baseAddress,
                          let dst = result.bindMemory(to: UInt8.self).baseAddress else { return }
                    for index in 0..<(targetWidth * targetHeight) {
                        dst[index * 3] = src[index * 4]
                        dst[index * 3 + 1] = src[index * 4 + 1]
                        dst[index * 3 + 2] = src[index * 4 + 2]
                    }
                }
            }
            pixels = compacted
        }

        return ComposedFilm(
            info: info, width: targetWidth, height: targetHeight,
            samplesPerPixel: samplesPerPixel, pixels: pixels)
    }
    #endif
}

extension ComposedFilm: CustomStringConvertible {
    public var description: String {
        "ComposedFilm(\(width)×\(height)\(isColor ? " RGB" : " gray"), \(info.summary))"
    }
}
