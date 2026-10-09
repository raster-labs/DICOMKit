// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (rendering)
//
// ParametricMapRenderer.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Renders DICOM parametric maps as colored visualizations
///
/// Supports rendering of quantitative parametric data with configurable color maps,
/// window/level settings, and threshold-based display. Maps physical quantity values
/// to colors for intuitive visualization.
///
/// Reference: PS3.3 C.8.23 - Parametric Map Modules
public struct ParametricMapRenderer: Sendable {
    
    // MARK: - Color Maps
    
    /// Predefined color maps for parametric visualization
    public enum ColorMap: Sendable {
        /// Grayscale (black to white)
        case grayscale
        
        /// Hot (black → red → yellow → white) - for heat maps
        case hot
        
        /// Cool (cyan → blue → magenta) - for cool color schemes
        case cool
        
        /// Jet (blue → cyan → yellow → red) - classic scientific visualization
        case jet
        
        /// Viridis (perceptually uniform, colorblind-friendly)
        case viridis
        
        /// Turbo (improved version of jet with better perceptual properties)
        case turbo
        
        /// Custom lookup table (value 0.0-1.0 → RGB)
        case custom([(r: Double, g: Double, b: Double)])
        
        /// Get RGB color for a normalized value (0.0 to 1.0)
        func color(for normalizedValue: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let clamped = max(0.0, min(1.0, normalizedValue))
            
            switch self {
            case .grayscale:
                let gray = UInt8(clamped * 255.0)
                return (gray, gray, gray)
                
            case .hot:
                return hotColorMap(clamped)
                
            case .cool:
                return coolColorMap(clamped)
                
            case .jet:
                return jetColorMap(clamped)
                
            case .viridis:
                return viridisColorMap(clamped)
                
            case .turbo:
                return turboColorMap(clamped)
                
            case .custom(let lut):
                return customColorMap(clamped, lut: lut)
            }
        }
        
        // MARK: - Color Map Implementations
        
        private func hotColorMap(_ value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let r = min(1.0, value * 2.0)
            let g = max(0.0, min(1.0, value * 2.0 - 0.5))
            let b = max(0.0, min(1.0, value * 3.0 - 2.0))
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }
        
        private func coolColorMap(_ value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let r = value
            let g = 1.0 - value
            let b = 1.0
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }
        
        private func jetColorMap(_ value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            let r = max(0.0, min(1.0, 1.5 - abs(4.0 * value - 3.0)))
            let g = max(0.0, min(1.0, 1.5 - abs(4.0 * value - 2.0)))
            let b = max(0.0, min(1.0, 1.5 - abs(4.0 * value - 1.0)))
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }
        
        private func viridisColorMap(_ value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            // Simplified viridis approximation
            let r = 0.27 + 0.10 * value + 0.20 * pow(value, 4)
            let g = 0.00 + 0.85 * pow(value, 0.6)
            let b = 0.33 + 0.56 * value - 0.64 * pow(value, 2)
            return (UInt8(max(0, min(1, r)) * 255), UInt8(max(0, min(1, g)) * 255), UInt8(max(0, min(1, b)) * 255))
        }
        
        private func turboColorMap(_ value: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
            // Simplified turbo approximation
            let r = max(0.0, min(1.0, (value < 0.5) ? 0.0 : 2.0 * (value - 0.5)))
            let g = max(0.0, min(1.0, (value < 0.5) ? 2.0 * value : 2.0 * (1.0 - value)))
            let b = max(0.0, min(1.0, (value < 0.5) ? 1.0 - 2.0 * value : 0.0))
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
        }
        
        private func customColorMap(_ value: Double, lut: [(r: Double, g: Double, b: Double)]) -> (r: UInt8, g: UInt8, b: UInt8) {
            guard !lut.isEmpty else {
                return (0, 0, 0)
            }
            
            let index = value * Double(lut.count - 1)
            let lowerIndex = Int(floor(index))
            let upperIndex = min(lowerIndex + 1, lut.count - 1)
            let fraction = index - Double(lowerIndex)
            
            let lower = lut[lowerIndex]
            let upper = lut[upperIndex]
            
            let r = lower.r + fraction * (upper.r - lower.r)
            let g = lower.g + fraction * (upper.g - lower.g)
            let b = lower.b + fraction * (upper.b - lower.b)
            
            return (UInt8(max(0, min(1, r)) * 255), UInt8(max(0, min(1, g)) * 255), UInt8(max(0, min(1, b)) * 255))
        }
    }
    
    // MARK: - Render Options
    
    /// Options for rendering parametric maps
    public struct RenderOptions: Sendable {
        /// Color map to use for visualization
        public var colorMap: ColorMap
        
        /// Window center (middle of displayed value range)
        public var windowCenter: Double
        
        /// Window width (range of displayed values)
        public var windowWidth: Double
        
        /// Minimum threshold (values below are transparent/black)
        public var minimumThreshold: Double?
        
        /// Maximum threshold (values above are saturated)
        public var maximumThreshold: Double?
        
        /// Background color for transparent/below-threshold areas (RGB, 0-255)
        public var backgroundColor: (r: UInt8, g: UInt8, b: UInt8)
        
        /// Initialize render options
        /// - Parameters:
        ///   - colorMap: Color map (default: hot)
        ///   - windowCenter: Window center (default: 0.0)
        ///   - windowWidth: Window width (default: 1.0)
        ///   - minimumThreshold: Minimum threshold (default: nil)
        ///   - maximumThreshold: Maximum threshold (default: nil)
        ///   - backgroundColor: Background color (default: black)
        public init(
            colorMap: ColorMap = .hot,
            windowCenter: Double = 0.0,
            windowWidth: Double = 1.0,
            minimumThreshold: Double? = nil,
            maximumThreshold: Double? = nil,
            backgroundColor: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
        ) {
            self.colorMap = colorMap
            self.windowCenter = windowCenter
            self.windowWidth = max(0.001, windowWidth)  // Prevent divide by zero
            self.minimumThreshold = minimumThreshold
            self.maximumThreshold = maximumThreshold
            self.backgroundColor = backgroundColor
        }
        
        /// Create options with auto-windowing based on data range
        /// - Parameters:
        ///   - values: Parametric values to analyze
        ///   - colorMap: Color map to use
        ///   - percentile: Percentile for auto-windowing (default: 99%)
        /// - Returns: Render options with auto-windowing
        public static func autoWindow(
            from values: [Double],
            colorMap: ColorMap = .hot,
            percentile: Double = 0.99
        ) -> RenderOptions {
            guard !values.isEmpty else {
                return RenderOptions(colorMap: colorMap)
            }
            
            let sorted = values.sorted()
            let minValue = sorted.first ?? 0.0
            let maxValue = sorted[Int(Double(sorted.count - 1) * percentile)]
            
            let windowWidth = maxValue - minValue
            let windowCenter = (maxValue + minValue) / 2.0
            
            return RenderOptions(
                colorMap: colorMap,
                windowCenter: windowCenter,
                windowWidth: windowWidth,
                minimumThreshold: minValue
            )
        }
    }
    
    // MARK: - Rendering Methods
    
    /// Render parametric map as a CGImage
    ///
    /// Creates a colored visualization from parametric values using the specified
    /// color map and windowing settings. Values are normalized to 0.0-1.0 range
    /// based on window center/width, then mapped to colors.
    ///
    /// - Parameters:
    ///   - values: Array of parametric values (physical quantities)
    ///   - width: Image width in pixels
    ///   - height: Image height in pixels
    ///   - options: Rendering options (color map, windowing, thresholds)
    /// - Returns: CGImage containing the rendered parametric map, or nil if rendering fails
    public static func render(
        values: [Double],
        width: Int,
        height: Int,
        options: RenderOptions = RenderOptions()
    ) -> CGImage? {
        guard width > 0 && height > 0 else {
            return nil
        }
        
        let totalPixels = width * height
        
        guard values.count == totalPixels else {
            return nil
        }
        
        // Create RGB output buffer
        var outputBytes = [UInt8](repeating: 0, count: totalPixels * 3)
        
        // Calculate window bounds
        let windowMin = options.windowCenter - options.windowWidth / 2.0
        let windowMax = options.windowCenter + options.windowWidth / 2.0
        
        // Render each pixel
        for i in 0..<totalPixels {
            let value = values[i]
            
            // Apply thresholds
            if let minThreshold = options.minimumThreshold, value < minThreshold {
                let offset = i * 3
                outputBytes[offset] = options.backgroundColor.r
                outputBytes[offset + 1] = options.backgroundColor.g
                outputBytes[offset + 2] = options.backgroundColor.b
                continue
            }
            
            if let maxThreshold = options.maximumThreshold, value > maxThreshold {
                let normalizedValue = 1.0
                let color = options.colorMap.color(for: normalizedValue)
                let offset = i * 3
                outputBytes[offset] = color.r
                outputBytes[offset + 1] = color.g
                outputBytes[offset + 2] = color.b
                continue
            }
            
            // Normalize value to 0.0-1.0 based on window
            let normalizedValue = (value - windowMin) / (windowMax - windowMin)
            let clampedValue = max(0.0, min(1.0, normalizedValue))
            
            // Map to color
            let color = options.colorMap.color(for: clampedValue)
            
            let offset = i * 3
            outputBytes[offset] = color.r
            outputBytes[offset + 1] = color.g
            outputBytes[offset + 2] = color.b
        }
        
        // Create CGImage from RGB buffer
        guard let dataProvider = CGDataProvider(data: Data(outputBytes) as CFData) else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: width * 3,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
    
    /// Render a parametric map frame from a ParametricMap object
    ///
    /// Convenience method that extracts pixel data and renders in one step.
    ///
    /// - Parameters:
    ///   - parametricMap: The Parametric Map object
    ///   - pixelData: The pixel data from the DICOM file
    ///   - frameIndex: The frame index to render (0-based)
    ///   - options: Rendering options (default: auto-windowing with hot color map)
    /// - Returns: CGImage containing the rendered frame, or nil if rendering fails
    public static func renderFrame(
        from parametricMap: ParametricMap,
        pixelData: Data,
        frameIndex: Int,
        options: RenderOptions? = nil
    ) -> CGImage? {
        // Extract parametric values
        guard let values = ParametricMapPixelDataExtractor.extractFrame(
            from: parametricMap,
            pixelData: pixelData,
            frameIndex: frameIndex
        ) else {
            return nil
        }
        
        // Use auto-windowing if no options provided
        let renderOptions = options ?? RenderOptions.autoWindow(from: values, colorMap: .hot)
        
        // Render the frame
        return render(
            values: values,
            width: parametricMap.columns,
            height: parametricMap.rows,
            options: renderOptions
        )
    }
}

#endif
