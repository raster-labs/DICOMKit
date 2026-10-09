// NEMA-verified: 2026a, checked 2026-09-30 — CIELab decoding per PS3.3 2026a C.10.7.1.1; LABELMAP rendering reads the Segment Number from the pixel value per C.8.20.2.3.3 and treats Pixel Padding Value as background per C.8.20.2.4; a PALETTE COLOR LABELMAP takes segment colours from its Palette Color Lookup Table (Table C.8.20-2, C.7.6.3.1.5)
//
// SegmentationRenderer.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders DICOM segmentation overlays on images
///
/// Supports rendering of segmentation masks as colored overlays with configurable
/// opacity and visibility settings. Handles CIELab to RGB color conversion and
/// multi-segment compositing.
///
/// Reference: PS3.3 C.8.20 - Segmentation Modules
public struct SegmentationRenderer: Sendable {
    
    // MARK: - Render Options
    
    /// Options for rendering segmentation overlays
    public struct RenderOptions: Sendable {
        /// Opacity for segment overlays (0.0 = fully transparent, 1.0 = fully opaque)
        public var opacity: Double
        
        /// Visible segments (nil = all segments visible)
        public var visibleSegments: Set<Int>?
        
        /// Custom colors for specific segments (RGB, 0-255)
        /// If not specified, uses segment's recommended display color or default palette
        public var customColors: [Int: (r: UInt8, g: UInt8, b: UInt8)]?
        
        /// Initialize render options with default values
        /// - Parameters:
        ///   - opacity: Opacity for overlays (default 0.5)
        ///   - visibleSegments: Set of visible segment numbers (default nil = all visible)
        ///   - customColors: Dictionary of custom colors per segment (default nil)
        public init(
            opacity: Double = 0.5,
            visibleSegments: Set<Int>? = nil,
            customColors: [Int: (r: UInt8, g: UInt8, b: UInt8)]? = nil
        ) {
            self.opacity = max(0.0, min(1.0, opacity))
            self.visibleSegments = visibleSegments
            self.customColors = customColors
        }
    }
    
    // MARK: - Rendering Methods
    
    /// Render segmentation overlay as a CGImage
    ///
    /// Creates a colored overlay image from segment masks. Each segment is rendered
    /// with its assigned color and the specified opacity. Overlapping segments are
    /// blended with later segments taking priority.
    ///
    /// - Parameters:
    ///   - segmentation: The segmentation object with segment definitions
    ///   - segmentMasks: Dictionary mapping segment numbers to mask arrays
    ///   - options: Rendering options (opacity, visibility, colors)
    /// - Returns: CGImage containing the rendered overlay, or nil if rendering fails
    public static func renderOverlay(
        segmentation: Segmentation,
        segmentMasks: [Int: [UInt8]],
        options: RenderOptions = RenderOptions()
    ) -> CGImage? {
        let width = segmentation.columns
        let height = segmentation.rows
        
        guard width > 0 && height > 0 else {
            return nil
        }
        
        let totalPixels = width * height
        
        // Create RGBA output buffer
        var outputBytes = [UInt8](repeating: 0, count: totalPixels * 4)
        
        // Get segment colors
        let segmentColors = buildSegmentColorMap(from: segmentation, customColors: options.customColors)
        
        // Render each visible segment
        for segment in segmentation.segments {
            let segmentNumber = segment.segmentNumber
            
            // Check visibility
            if let visibleSegments = options.visibleSegments,
               !visibleSegments.contains(segmentNumber) {
                continue
            }
            
            guard let mask = segmentMasks[segmentNumber] else {
                continue
            }
            
            guard mask.count == totalPixels else {
                continue
            }
            
            guard let color = segmentColors[segmentNumber] else {
                continue
            }
            
            // Blend this segment into the output
            for pixelIndex in 0..<totalPixels {
                let maskValue = mask[pixelIndex]
                
                // Skip fully transparent pixels
                guard maskValue > 0 else {
                    continue
                }
                
                let offset = pixelIndex * 4
                
                // Calculate opacity for this pixel
                let pixelOpacity = Double(maskValue) / 255.0 * options.opacity
                
                // Get current background color
                let bgR = Double(outputBytes[offset])
                let bgG = Double(outputBytes[offset + 1])
                let bgB = Double(outputBytes[offset + 2])
                let bgA = Double(outputBytes[offset + 3]) / 255.0
                
                // Blend segment color over background
                let fgR = Double(color.r)
                let fgG = Double(color.g)
                let fgB = Double(color.b)
                
                // Alpha compositing
                let outA = pixelOpacity + bgA * (1.0 - pixelOpacity)
                
                if outA > 0 {
                    let outR = (fgR * pixelOpacity + bgR * bgA * (1.0 - pixelOpacity)) / outA
                    let outG = (fgG * pixelOpacity + bgG * bgA * (1.0 - pixelOpacity)) / outA
                    let outB = (fgB * pixelOpacity + bgB * bgA * (1.0 - pixelOpacity)) / outA
                    
                    outputBytes[offset] = UInt8(max(0, min(255, outR)))
                    outputBytes[offset + 1] = UInt8(max(0, min(255, outG)))
                    outputBytes[offset + 2] = UInt8(max(0, min(255, outB)))
                    outputBytes[offset + 3] = UInt8(max(0, min(255, outA * 255.0)))
                } else {
                    outputBytes[offset] = 0
                    outputBytes[offset + 1] = 0
                    outputBytes[offset + 2] = 0
                    outputBytes[offset + 3] = 0
                }
            }
        }
        
        return createRGBACGImage(from: outputBytes, width: width, height: height)
    }
    
    /// Render one frame of a LABELMAP segmentation as a colored overlay
    ///
    /// Each pixel's value is the Segment Number of the segment present there (PS3.3
    /// C.8.20.2.3.3); it is painted with that segment's color at `options.opacity`. Pixels
    /// whose value is the Pixel Padding Value (the background segment, C.8.20.2.4), belongs
    /// to a hidden segment, or is not described by any segment stay transparent.
    ///
    /// - Parameters:
    ///   - segmentation: A segmentation whose type is `.labelmap`
    ///   - pixelData: The raw pixel data of all frames
    ///   - frameIndex: The frame (slice) to render, 0-based
    ///   - options: Rendering options (opacity, visibility, colors)
    /// - Returns: CGImage containing the rendered overlay, or nil if the segmentation is not
    ///   a LABELMAP or the frame cannot be read
    public static func renderLabelmap(
        segmentation: Segmentation,
        pixelData: Data,
        frameIndex: Int = 0,
        options: RenderOptions = RenderOptions()
    ) -> CGImage? {
        guard segmentation.segmentationType == .labelmap,
              let labels = SegmentationPixelDataExtractor.extractLabelmapFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: segmentation.rows,
                columns: segmentation.columns,
                bitsAllocated: segmentation.bitsAllocated
              ) else {
            return nil
        }

        let width = segmentation.columns
        let height = segmentation.rows
        let segmentColors = buildSegmentColorMap(from: segmentation, customColors: options.customColors)
        let alpha = UInt8(max(0, min(255, options.opacity * 255.0)))

        var outputBytes = [UInt8](repeating: 0, count: width * height * 4)
        for (pixelIndex, label) in labels.enumerated() {
            let segmentNumber = Int(label)
            if let padding = segmentation.pixelPaddingValue, segmentNumber == padding {
                continue
            }
            if let visible = options.visibleSegments, !visible.contains(segmentNumber) {
                continue
            }
            guard let color = segmentColors[segmentNumber] else {
                continue
            }
            let offset = pixelIndex * 4
            // Premultiplied RGBA
            outputBytes[offset] = UInt8((Int(color.r) * Int(alpha)) / 255)
            outputBytes[offset + 1] = UInt8((Int(color.g) * Int(alpha)) / 255)
            outputBytes[offset + 2] = UInt8((Int(color.b) * Int(alpha)) / 255)
            outputBytes[offset + 3] = alpha
        }

        return createRGBACGImage(from: outputBytes, width: width, height: height)
    }

    /// Composite segmentation overlay with a base image
    ///
    /// Renders the segmentation overlay and composites it over the provided base image.
    /// The base image and segmentation must have the same dimensions.
    ///
    /// - Parameters:
    ///   - baseImage: The base image to overlay segmentations on
    ///   - segmentation: The segmentation object with segment definitions
    ///   - segmentMasks: Dictionary mapping segment numbers to mask arrays
    ///   - options: Rendering options (opacity, visibility, colors)
    /// - Returns: CGImage with composited overlay, or nil if rendering fails
    public static func compositeWithImage(
        baseImage: CGImage,
        segmentation: Segmentation,
        segmentMasks: [Int: [UInt8]],
        options: RenderOptions = RenderOptions()
    ) -> CGImage? {
        // Verify dimensions match
        guard baseImage.width == segmentation.columns &&
              baseImage.height == segmentation.rows else {
            return nil
        }
        
        // Render the overlay
        guard let overlay = renderOverlay(
            segmentation: segmentation,
            segmentMasks: segmentMasks,
            options: options
        ) else {
            return nil
        }
        
        // Create compositing context
        let width = baseImage.width
        let height = baseImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        // Draw base image
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw overlay
        context.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    // MARK: - Color Conversion
    
    /// Convert CIELab color to RGB
    ///
    /// Performs approximate CIELab to RGB conversion for display purposes.
    /// DICOM uses 16-bit unsigned CIELab values (0-65535).
    ///
    /// Reference: PS3.3 C.10.7.1.1 - Recommended Display CIELab Value
    ///
    /// - Parameter cielab: CIELab color from segmentation
    /// - Returns: RGB color tuple (0-255)
    public static func cielabToRGB(_ cielab: CIELabColor) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Convert from DICOM's 16-bit unsigned representation to standard CIELab ranges
        // L*: 0-65535 maps to 0-100
        // a*: 0-65535 maps to -128 to +127 (32768 = 0)
        // b*: 0-65535 maps to -128 to +127 (32768 = 0)
        
        let L = Double(cielab.l) * 100.0 / 65535.0
        let a = (Double(cielab.a) - 32768.0) * 255.0 / 65535.0
        let b = (Double(cielab.b) - 32768.0) * 255.0 / 65535.0
        
        // Convert Lab to XYZ (D65 illuminant)
        let fy = (L + 16.0) / 116.0
        let fx = a / 500.0 + fy
        let fz = fy - b / 200.0
        
        let xr = fx > 0.206897 ? fx * fx * fx : (fx - 16.0 / 116.0) / 7.787
        let yr = fy > 0.206897 ? fy * fy * fy : (fy - 16.0 / 116.0) / 7.787
        let zr = fz > 0.206897 ? fz * fz * fz : (fz - 16.0 / 116.0) / 7.787
        
        // D65 reference white
        let X = xr * 95.047
        let Y = yr * 100.000
        let Z = zr * 108.883
        
        // Convert XYZ to RGB (sRGB color space)
        var R = X *  3.2406 + Y * -1.5372 + Z * -0.4986
        var G = X * -0.9689 + Y *  1.8758 + Z *  0.0415
        var B = X *  0.0557 + Y * -0.2040 + Z *  1.0570
        
        // Apply gamma correction (sRGB)
        R = R > 0.0031308 ? 1.055 * pow(R, 1.0 / 2.4) - 0.055 : 12.92 * R
        G = G > 0.0031308 ? 1.055 * pow(G, 1.0 / 2.4) - 0.055 : 12.92 * G
        B = B > 0.0031308 ? 1.055 * pow(B, 1.0 / 2.4) - 0.055 : 12.92 * B
        
        // Scale to 0-255 and clamp
        let r = UInt8(max(0, min(255, R * 255.0)))
        let g = UInt8(max(0, min(255, G * 255.0)))
        let bOut = UInt8(max(0, min(255, B * 255.0)))
        
        return (r, g, bOut)
    }
    
    // MARK: - Private Helpers
    
    /// Build a map of segment numbers to RGB colors
    private static func buildSegmentColorMap(
        from segmentation: Segmentation,
        customColors: [Int: (r: UInt8, g: UInt8, b: UInt8)]?
    ) -> [Int: (r: UInt8, g: UInt8, b: UInt8)] {
        var colorMap: [Int: (r: UInt8, g: UInt8, b: UInt8)] = [:]
        
        for segment in segmentation.segments {
            let segmentNumber = segment.segmentNumber
            
            // Check for custom color first
            if let customColor = customColors?[segmentNumber] {
                colorMap[segmentNumber] = customColor
                continue
            }
            
            // Use segment's recommended display color if available
            if let cielab = segment.recommendedDisplayCIELabValue {
                colorMap[segmentNumber] = cielabToRGB(cielab)
                continue
            }

            // A PALETTE COLOR LABELMAP carries its colours in the Palette Color Lookup
            // Table, indexed by the stored pixel value = Segment Number (PS3.3 2026a
            // Table C.8.20-2, C.7.6.3.1.5), and has no CIELab value
            if segmentation.photometricInterpretation == "PALETTE COLOR",
               let lut = segmentation.paletteColorLookupTable {
                let color = lut.lookup(segmentNumber)
                colorMap[segmentNumber] = (r: color.red, g: color.green, b: color.blue)
                continue
            }
            
            // Fall back to default color palette
            colorMap[segmentNumber] = defaultColor(for: segmentNumber)
        }
        
        return colorMap
    }
    
    /// Get default color for a segment number
    ///
    /// Provides a distinctive color palette for segments without specified colors.
    private static func defaultColor(for segmentNumber: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Default color palette with high contrast and medical imaging conventions
        let palette: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0),      // Red
            (0, 255, 0),      // Green
            (0, 0, 255),      // Blue
            (255, 255, 0),    // Yellow
            (255, 0, 255),    // Magenta
            (0, 255, 255),    // Cyan
            (255, 128, 0),    // Orange
            (128, 0, 255),    // Purple
            (0, 255, 128),    // Spring Green
            (255, 0, 128),    // Rose
            (128, 255, 0),    // Chartreuse
            (0, 128, 255),    // Azure
            (255, 128, 128),  // Light Red
            (128, 255, 128),  // Light Green
            (128, 128, 255),  // Light Blue
            (255, 255, 128),  // Light Yellow
        ]
        
        // Segment numbers are 1-based per DICOM, but guard against a malformed
        // value of 0 (or negative) so we don't index the palette with -1.
        let index = ((segmentNumber - 1) % palette.count + palette.count) % palette.count
        return palette[index]
    }
    
    /// Create an RGBA CGImage from pixel bytes
    private static func createRGBACGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
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
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

#endif
