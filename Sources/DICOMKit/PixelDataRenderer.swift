// NEMA-verified: 2026a, checked 2026-09-30 — Pixel Cells read Bits Allocated wide on every path (PS3.5 2026a 8.1.1, D67); monochrome frames render through GrayscaleDisplayPipeline or its table (PS3.4 N.2, P-PIPELINE); the auto window is the C.11.2.1.2.1 full-range window (D66)
// NEMA-verified: 2026a, checked 2026-09-29 — YBR_FULL/YBR_FULL_422 (full-range), YBR_PARTIAL_420/422 (partial-range, Y−16) inverse equations and the packed 4:2:2 layout follow PS3.3 2026a C.7.6.3.1.2; YBR_ICT/YBR_RCT are JPEG 2000 codestream transforms already inverted by the decoder and are not re-converted (P-RENDER)
import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders DICOM pixel data to CGImage for display
///
/// Supports rendering of uncompressed DICOM images including:
/// - MONOCHROME1 and MONOCHROME2 grayscale images
/// - RGB color images
/// - PALETTE COLOR images with lookup tables
/// - 8-bit, 12-bit, and 16-bit images
/// - Multi-frame images (individual frame rendering)
///
/// Reference: DICOM PS3.3 C.7.6.3 - Image Pixel Module
public struct PixelDataRenderer: Sendable {
    /// The pixel data to render
    public let pixelData: PixelData
    
    /// Optional palette color lookup table for PALETTE COLOR images
    public let paletteColorLUT: PaletteColorLUT?
    
    /// Creates a new renderer for the specified pixel data
    /// - Parameter pixelData: The pixel data to render
    public init(pixelData: PixelData) {
        self.pixelData = pixelData
        self.paletteColorLUT = nil
    }
    
    /// Creates a new renderer for the specified pixel data with a palette color LUT
    /// - Parameters:
    ///   - pixelData: The pixel data to render
    ///   - paletteColorLUT: Palette color lookup table for PALETTE COLOR images
    public init(pixelData: PixelData, paletteColorLUT: PaletteColorLUT?) {
        self.pixelData = pixelData
        self.paletteColorLUT = paletteColorLUT
    }
    
    // MARK: - CGImage Rendering
    
    /// Renders a frame to a CGImage using default settings
    ///
    /// For monochrome images, calculates window settings from the actual pixel range.
    /// For palette color images, uses the palette lookup table if provided.
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds, nil otherwise
    public func renderFrame(_ frameIndex: Int = 0) -> CGImage? {
        let descriptor = pixelData.descriptor
        
        if descriptor.photometricInterpretation.isMonochrome {
            // Calculate auto window from actual pixel range
            guard let range = pixelData.pixelRange(forFrame: frameIndex) else {
                return nil
            }
            
            // The full input range x1…x2: PS3.3 C.11.2.1.2.1, "a Window Center of
            // (x1+x2+1)/2 and a Window Width of (x2-x1+1) selects the range of input
            // values from x1 to x2" (D66).
            let window = WindowSettings(center: Double(range.min + range.max + 1) / 2.0,
                                        width: Double(range.max - range.min + 1))
            
            return renderMonochromeFrame(frameIndex, window: window)
        } else if descriptor.photometricInterpretation.isPaletteColor {
            return renderPaletteColorFrame(frameIndex)
        } else {
            return renderColorFrame(frameIndex)
        }
    }
    
    /// Renders a monochrome frame to a CGImage with specified window settings
    /// - Parameters:
    ///   - frameIndex: The frame index to render (default 0)
    ///   - window: Window settings for grayscale mapping
    /// - Returns: CGImage if rendering succeeds, nil otherwise
    public func renderMonochromeFrame(_ frameIndex: Int = 0, window: WindowSettings) -> CGImage? {
        let descriptor = pixelData.descriptor

        guard descriptor.photometricInterpretation.isMonochrome else {
            return nil
        }

        // Cells wider than two bytes (Bits Allocated 32) cannot index a table; the same
        // chain — window, then MONOCHROME1 inversion — is evaluated per pixel (D67).
        guard WindowLUT.canTabulate(descriptor) || descriptor.bytesPerSample < 1 else {
            return renderMonochromeFrame(
                frameIndex,
                pipeline: .standard(for: descriptor.photometricInterpretation, voiLUT: VOILUT(window)))
        }

        return renderMonochromeFrame(
            frameIndex, displayTable: WindowLUT.grayscale(descriptor: descriptor, window: window))
    }

    /// Renders a monochrome frame through a raw-cell → display-byte table (256 or
    /// 65,536 entries), such as a `WindowLUT` or `GrayscaleDisplayPipeline.table(for:)`.
    ///
    /// - Returns: `nil` for a non-monochrome frame, a missing frame, or cells wider
    ///   than the table covers.
    public func renderMonochromeFrame(_ frameIndex: Int = 0, displayTable lut: WindowLUT) -> CGImage? {
        let descriptor = pixelData.descriptor

        guard descriptor.photometricInterpretation.isMonochrome else {
            return nil
        }

        guard let frameData = pixelData.frameData(at: frameIndex) else {
            return nil
        }

        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        
        // Create grayscale output buffer
        var outputBytes = [UInt8](repeating: 0, count: totalPixels)

        let bytesPerSample = descriptor.bytesPerSample
        guard bytesPerSample >= 1 else {
            return createGrayscaleCGImage(from: outputBytes, width: width, height: height)
        }

        // The whole per-pixel chain — shift, stored-bit mask, sign extension, the VOI
        // window, MONOCHROME1 inversion and the clamp to a byte — depends on nothing
        // but the raw sample, so it is evaluated once per possible sample value rather
        // than once per pixel. `WindowLUT` builds the table with the same
        // `WindowSettings.apply` this loop used to call, so the output is byte-identical.
        let expectedEntries = bytesPerSample == 1 ? 256 : 65_536
        guard bytesPerSample <= 2, lut.count >= expectedEntries else { return nil }

        // Samples that would read past the end of the frame are left at 0, matching
        // the bounds check the scalar loop broke out on.
        let availablePixels = min(totalPixels, frameData.count / bytesPerSample)

        frameData.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            lut.table.withUnsafeBufferPointer { table in
                outputBytes.withUnsafeMutableBufferPointer { output in
                    if bytesPerSample == 1 {
                        for i in 0..<availablePixels {
                            output[i] = table[Int(source[i])]
                        }
                    } else {
                        for i in 0..<availablePixels {
                            let offset = i * bytesPerSample
                            let low = Int(source[offset])
                            let high = Int(source[offset + 1])
                            output[i] = table[low | (high << 8)]
                        }
                    }
                }
            }
        }

        return createGrayscaleCGImage(from: outputBytes, width: width, height: height)
    }
    
    /// Renders a monochrome frame through the PS3.4 N.2 grayscale chain — Modality
    /// LUT, VOI, Presentation LUT (P-PIPELINE) — optionally recoloured through a
    /// reader's pseudo-colour entries indexed by the display byte.
    ///
    /// Cells of one or two bytes go through the chain's table; wider cells (Bits
    /// Allocated 32) are read whole (PS3.5 8.1.1) and evaluated per pixel (D67). The
    /// two give the same bytes for the same stored value.
    public func renderMonochromeFrame(
        _ frameIndex: Int = 0,
        pipeline: GrayscaleDisplayPipeline,
        pseudoColor entries: [(red: UInt8, green: UInt8, blue: UInt8)]? = nil
    ) -> CGImage? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation.isMonochrome, descriptor.bytesPerSample >= 1 else {
            return nil
        }
        let colours = (entries?.isEmpty ?? true) ? nil : entries

        if let table = pipeline.table(for: descriptor) {
            if let colours {
                return renderMonochromeFrame(
                    frameIndex, displayLUT: PaletteDisplayLUT.make(window: table, entries: colours))
            }
            return renderMonochromeFrame(frameIndex, displayTable: table)
        }

        guard let frameData = pixelData.frameData(at: frameIndex) else { return nil }
        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        let bytesPerSample = descriptor.bytesPerSample
        var grey = [UInt8](repeating: 0, count: totalPixels)
        frameData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<totalPixels {
                let offset = i * bytesPerSample
                guard offset + bytesPerSample <= bytes.count else { break }
                let stored = descriptor.storedValue(fromCell: descriptor.cellValue(in: bytes, at: offset))
                grey[i] = pipeline.displayByte(forStoredValue: stored, descriptor: descriptor)
            }
        }
        guard let colours else {
            return createGrayscaleCGImage(from: grey, width: width, height: height)
        }
        let last = colours.count - 1
        var rgba = [UInt8](repeating: 255, count: totalPixels * 4)
        for i in 0..<totalPixels {
            let entry = colours[min(last, Int(grey[i]))]
            rgba[i * 4] = entry.red
            rgba[i * 4 + 1] = entry.green
            rgba[i * 4 + 2] = entry.blue
        }
        return createRGBACGImage(from: rgba, width: width, height: height)
    }

    /// Renders a color frame to a CGImage
    ///
    /// Handles RGB and YBR color images with 3 samples per pixel.
    /// For PALETTE COLOR images, use renderPaletteColorFrame instead.
    ///
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds, nil otherwise
    public func renderColorFrame(_ frameIndex: Int = 0) -> CGImage? {
        let descriptor = pixelData.descriptor
        
        // Only handle RGB/YBR color images, not PALETTE COLOR
        guard descriptor.photometricInterpretation.isColor,
              !descriptor.photometricInterpretation.isPaletteColor else {
            return nil
        }
        
        guard descriptor.samplesPerPixel == 3 else {
            return nil
        }

        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height

        // YBR_FULL_422 (and the retired YBR_PARTIAL_422) in Native format is packed
        // "Y1 Y2 Cb Cr" per pixel pair, so a frame is Rows × Columns × 2 bytes, not
        // × 3 (PS3.3 C.7.6.3.1.2). Unpack it to full-resolution samples first.
        if let packed = packed422Frame(frameIndex) {
            var outputBytes = [UInt8](repeating: 255, count: totalPixels * 4)
            let fullRange = descriptor.photometricInterpretation == .ybrFull422
            for pair in 0..<(totalPixels / 2) {
                let base = pair * 4
                let y1 = Double(packed[base])
                let y2 = Double(packed[base + 1])
                let cb = Double(packed[base + 2])
                let cr = Double(packed[base + 3])
                for (slot, y) in [(0, y1), (1, y2)] {
                    let (r, g, b) = fullRange
                        ? Self.ybrFullToRGB(y: y, cb: cb, cr: cr)
                        : Self.ybrPartialToRGB(y: y, cb: cb, cr: cr)
                    let outputOffset = (pair * 2 + slot) * 4
                    outputBytes[outputOffset] = r
                    outputBytes[outputOffset + 1] = g
                    outputBytes[outputOffset + 2] = b
                    outputBytes[outputOffset + 3] = 255
                }
            }
            return createRGBACGImage(from: outputBytes, width: width, height: height)
        }

        guard let frameData = pixelData.frameData(at: frameIndex) else {
            return nil
        }

        // Create RGB output buffer (4 bytes per pixel: RGBA)
        var outputBytes = [UInt8](repeating: 255, count: totalPixels * 4)

        let bytesPerSample = descriptor.bytesPerSample
        let planarConfig = descriptor.planarConfiguration
        let bitShift = descriptor.bitShift
        let storedBitMask = descriptor.storedBitMask
        let maxValue = (1 << descriptor.bitsStored) - 1
        
        for pixelIndex in 0..<totalPixels {
            var r: Int = 0
            var g: Int = 0
            var b: Int = 0
            
            if planarConfig == 0 {
                // Color-by-pixel: R1G1B1R2G2B2...
                let baseOffset = pixelIndex * 3 * bytesPerSample
                
                if bytesPerSample == 1 {
                    if baseOffset + 2 < frameData.count {
                        r = Int(frameData[baseOffset])
                        g = Int(frameData[baseOffset + 1])
                        b = Int(frameData[baseOffset + 2])
                    }
                } else if bytesPerSample > 2 {
                    // Whole cells, Bits Allocated wide (PS3.5 8.1.1, D67).
                    if baseOffset + 3 * bytesPerSample <= frameData.count {
                        (r, g, b) = frameData.withUnsafeBytes { bytes in
                            (descriptor.cellValue(in: bytes, at: baseOffset),
                             descriptor.cellValue(in: bytes, at: baseOffset + bytesPerSample),
                             descriptor.cellValue(in: bytes, at: baseOffset + 2 * bytesPerSample))
                        }
                    }
                } else {
                    if baseOffset + 5 < frameData.count {
                        r = Int(frameData[baseOffset]) | (Int(frameData[baseOffset + 1]) << 8)
                        g = Int(frameData[baseOffset + 2]) | (Int(frameData[baseOffset + 3]) << 8)
                        b = Int(frameData[baseOffset + 4]) | (Int(frameData[baseOffset + 5]) << 8)
                    }
                }
            } else {
                // Color-by-plane: R1R2...G1G2...B1B2...
                let planeSize = totalPixels * bytesPerSample
                let rOffset = pixelIndex * bytesPerSample
                let gOffset = planeSize + pixelIndex * bytesPerSample
                let bOffset = 2 * planeSize + pixelIndex * bytesPerSample
                
                if bytesPerSample == 1 {
                    if bOffset < frameData.count {
                        r = Int(frameData[rOffset])
                        g = Int(frameData[gOffset])
                        b = Int(frameData[bOffset])
                    }
                } else if bytesPerSample > 2 {
                    if bOffset + bytesPerSample <= frameData.count {
                        (r, g, b) = frameData.withUnsafeBytes { bytes in
                            (descriptor.cellValue(in: bytes, at: rOffset),
                             descriptor.cellValue(in: bytes, at: gOffset),
                             descriptor.cellValue(in: bytes, at: bOffset))
                        }
                    }
                } else {
                    if bOffset + 1 < frameData.count {
                        r = Int(frameData[rOffset]) | (Int(frameData[rOffset + 1]) << 8)
                        g = Int(frameData[gOffset]) | (Int(frameData[gOffset + 1]) << 8)
                        b = Int(frameData[bOffset]) | (Int(frameData[bOffset + 1]) << 8)
                    }
                }
            }
            
            // Apply bit masking
            r = (r >> bitShift) & storedBitMask
            g = (g >> bitShift) & storedBitMask
            b = (b >> bitShift) & storedBitMask
            
            // Normalize to 8-bit
            let scale = 255.0 / Double(maxValue)
            let outputOffset = pixelIndex * 4
            outputBytes[outputOffset] = UInt8(max(0, min(255, Double(r) * scale)))
            outputBytes[outputOffset + 1] = UInt8(max(0, min(255, Double(g) * scale)))
            outputBytes[outputOffset + 2] = UInt8(max(0, min(255, Double(b) * scale)))
            outputBytes[outputOffset + 3] = 255 // Alpha
        }
        
        // Convert YBR samples to RGB where the samples in the buffer are still YBR.
        switch descriptor.photometricInterpretation {
        case .ybrFull, .ybrFull422:
            convertYBRToRGB(&outputBytes, totalPixels: totalPixels, fullRange: true)
        case .ybrPartial420, .ybrPartial422:
            convertYBRToRGB(&outputBytes, totalPixels: totalPixels, fullRange: false)
        case .ybrICT, .ybrRCT:
            // YBR_ICT / YBR_RCT "shall only be used for pixel data in an Encapsulated
            // (compressed) format" and are the JPEG 2000 irreversible / reversible
            // component transforms of ISO/IEC 15444-1 (PS3.3 C.7.6.3.1.2). The JPEG
            // 2000 codestream signals the transform and the decoder inverts it as
            // part of decoding, so the decoded samples reaching this renderer are
            // already RGB. Converting again would corrupt the colours; do nothing.
            break
        default:
            break
        }

        return createRGBACGImage(from: outputBytes, width: width, height: height)
    }

    /// The packed bytes of a Native-format 4:2:2 frame, or nil when this is not one.
    ///
    /// Only YBR_FULL_422 (and the retired YBR_PARTIAL_422) with Bits Allocated 8 use
    /// the "two Y values followed by one CB and one CR value" layout of PS3.3
    /// C.7.6.3.1.2, giving a Value Length of Rows × Columns × Frames × 2 bytes.
    /// Codec-decoded 4:2:2 sources arrive here already upsampled to three full
    /// samples per pixel and are recognised by their frame length instead.
    private func packed422Frame(_ frameIndex: Int) -> Data? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation == .ybrFull422
                || descriptor.photometricInterpretation == .ybrPartial422,
              descriptor.bitsAllocated == 8,
              frameIndex >= 0, frameIndex < descriptor.numberOfFrames else { return nil }
        let packedFrameSize = descriptor.rows * descriptor.columns * 2
        guard (descriptor.rows * descriptor.columns) % 2 == 0,
              pixelData.data.count == packedFrameSize * descriptor.numberOfFrames else { return nil }
        let start = pixelData.data.startIndex + frameIndex * packedFrameSize
        return Data(pixelData.data[start..<(start + packedFrameSize)])
    }
    
    /// Renders a palette color frame to a CGImage
    ///
    /// Uses the palette color lookup table to convert indexed pixel values
    /// to RGB colors.
    ///
    /// Reference: DICOM PS3.3 C.7.6.3.1.5 - Palette Color Lookup Table Module
    ///
    /// - Parameter frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage if rendering succeeds, nil otherwise
    public func renderPaletteColorFrame(_ frameIndex: Int = 0) -> CGImage? {
        let descriptor = pixelData.descriptor
        
        guard descriptor.photometricInterpretation.isPaletteColor else {
            return nil
        }
        
        guard let lut = paletteColorLUT else {
            return nil
        }
        
        guard let frameData = pixelData.frameData(at: frameIndex) else {
            return nil
        }
        
        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        
        // Create RGB output buffer (4 bytes per pixel: RGBA)
        var outputBytes = [UInt8](repeating: 255, count: totalPixels * 4)
        
        let bytesPerSample = descriptor.bytesPerSample
        let bitShift = descriptor.bitShift
        let storedBitMask = descriptor.storedBitMask
        let isSigned = descriptor.isSigned
        let bitsStored = descriptor.bitsStored
        
        for pixelIndex in 0..<totalPixels {
            let offset = pixelIndex * bytesPerSample
            guard offset + bytesPerSample <= frameData.count else {
                break
            }
            
            // Read raw pixel value (index into LUT)
            let rawValue: Int
            if bytesPerSample == 1 {
                rawValue = Int(frameData[offset])
            } else if bytesPerSample > 2 {
                rawValue = frameData.withUnsafeBytes { descriptor.cellValue(in: $0, at: offset) }
            } else {
                let low = Int(frameData[offset])
                let high = Int(frameData[offset + 1])
                rawValue = low | (high << 8)
            }
            
            // Apply bit masking
            let shiftedValue = rawValue >> bitShift
            var maskedValue = shiftedValue & storedBitMask
            
            // Apply sign extension if needed
            if isSigned {
                let signBit = 1 << (bitsStored - 1)
                if maskedValue & signBit != 0 {
                    maskedValue = maskedValue - (1 << bitsStored)
                }
            }
            
            // Look up the color in the palette
            let (red, green, blue) = lut.lookup(maskedValue)
            
            // Write to output buffer
            let outputOffset = pixelIndex * 4
            outputBytes[outputOffset] = red
            outputBytes[outputOffset + 1] = green
            outputBytes[outputOffset + 2] = blue
            outputBytes[outputOffset + 3] = 255 // Alpha
        }
        
        return createRGBACGImage(from: outputBytes, width: width, height: height)
    }

    /// Renders a monochrome frame through display tables indexed by the raw
    /// assembled sample — the shape a pseudo-colour palette takes once its ramp
    /// has been folded into the window.
    ///
    /// The bit handling the palette-colour path performs is already baked into
    /// the tables (the window table was built over raw values), so this reads a
    /// sample and indexes, and nothing else. Deliberately the same loop shape,
    /// the same short-frame `break` and the same initial 255 fill as
    /// ``renderPaletteColorFrame(_:)``, so the two agree on the pixels past the
    /// end of a truncated frame — which is what the GPU equality tests compare.
    public func renderMonochromeFrame(
        _ frameIndex: Int = 0, displayLUT lut: PaletteDisplayLUT
    ) -> CGImage? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation.isMonochrome,
              let frameData = pixelData.frameData(at: frameIndex) else { return nil }

        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        guard width > 0, height > 0, lut.count > 0 else { return nil }

        var outputBytes = [UInt8](repeating: 255, count: totalPixels * 4)
        let bytesPerSample = descriptor.bytesPerSample
        let lastEntry = lut.count - 1

        for pixelIndex in 0..<totalPixels {
            let offset = pixelIndex * bytesPerSample
            guard offset + bytesPerSample <= frameData.count else { break }

            let rawValue: Int
            if bytesPerSample == 1 {
                rawValue = Int(frameData[offset])
            } else {
                rawValue = Int(frameData[offset]) | (Int(frameData[offset + 1]) << 8)
            }
            let index = min(lastEntry, rawValue)

            let outputOffset = pixelIndex * 4
            outputBytes[outputOffset] = lut.red[index]
            outputBytes[outputOffset + 1] = lut.green[index]
            outputBytes[outputOffset + 2] = lut.blue[index]
            outputBytes[outputOffset + 3] = 255
        }

        return createRGBACGImage(from: outputBytes, width: width, height: height)
    }

    // MARK: - Private Helpers
    
    /// Creates a grayscale CGImage from pixel bytes
    private func createGrayscaleCGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        let bytesPerRow = width
        
        guard let dataProvider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    
    /// Creates an RGBA CGImage from pixel bytes
    private func createRGBACGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        
        guard let dataProvider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    
    /// Converts 8-bit YBR samples (already normalised to 0…255) to RGB in place.
    ///
    /// - Parameter fullRange: `true` for YBR_FULL / YBR_FULL_422, `false` for
    ///   YBR_PARTIAL_420 / YBR_PARTIAL_422 (PS3.3 C.7.6.3.1.2).
    private func convertYBRToRGB(_ bytes: inout [UInt8], totalPixels: Int, fullRange: Bool) {
        for i in 0..<totalPixels {
            let offset = i * 4
            let y = Double(bytes[offset])
            let cb = Double(bytes[offset + 1])
            let cr = Double(bytes[offset + 2])
            let (r, g, b) = fullRange
                ? Self.ybrFullToRGB(y: y, cb: cb, cr: cr)
                : Self.ybrPartialToRGB(y: y, cb: cb, cr: cr)
            bytes[offset] = r
            bytes[offset + 1] = g
            bytes[offset + 2] = b
        }
    }

    /// YBR_FULL → RGB for Bits Allocated 8.
    ///
    /// Inverse of the PS3.3 C.7.6.3.1.2 YBR_FULL equations
    /// `Y = .2990R + .5870G + .1140B`, `CB = −.1687R − .3313G + .5000B + 128`,
    /// `CR = .5000R − .4187G − .0813B + 128` ("Black is represented by Y equal to
    /// zero. The absence of color is represented by both CB and CR values equal to
    /// half full scale."). The Y coefficient of the inverse is exactly 1.
    static func ybrFullToRGB(y: Double, cb: Double, cr: Double) -> (UInt8, UInt8, UInt8) {
        let cbc = cb - 128.0
        let crc = cr - 128.0
        let r = y + 1.402 * crc
        let g = y - 0.344136 * cbc - 0.714136 * crc
        let b = y + 1.772 * cbc
        return (clampToByte(r), clampToByte(g), clampToByte(b))
    }

    /// YBR_PARTIAL_420 / YBR_PARTIAL_422 → RGB for Bits Allocated 8.
    ///
    /// Inverse of the PS3.3 C.7.6.3.1.2 YBR_PARTIAL_420 equations
    /// `Y = .2568R + .5041G + .0979B + 16`, `CB = −.1482R − .2910G + .4392B + 128`,
    /// `CR = .4392R − .3678G − .0714B + 128`, where "black corresponds to Y = 16",
    /// "Y is restricted to 220 levels (i.e., the maximum value is 235)", "CB and CR
    /// each has a minimum value of 16" and "are restricted to 225 levels (i.e., the
    /// maximum value is 240)", "lack of color is represented by CB and CR equal to
    /// 128". Inverting that matrix gives the coefficients below (255/219 = 1.164384
    /// on Y; the near-zero cross terms of the exact inverse are dropped).
    static func ybrPartialToRGB(y: Double, cb: Double, cr: Double) -> (UInt8, UInt8, UInt8) {
        let yc = y - 16.0
        let cbc = cb - 128.0
        let crc = cr - 128.0
        let r = 1.164384 * yc + 1.596002 * crc
        let g = 1.164384 * yc - 0.391725 * cbc - 0.813013 * crc
        let b = 1.164384 * yc + 2.017291 * cbc
        return (clampToByte(r), clampToByte(g), clampToByte(b))
    }

    private static func clampToByte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }
}

#endif
