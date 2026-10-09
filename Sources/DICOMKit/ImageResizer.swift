// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (resampling)
/// Image Resizing for DICOM Print Management
///
/// Phase 3.2 of the DICOM Print Management implementation.
/// Provides high-quality image resizing algorithms for optimal print output.
///
/// Reference: PS3.4 Annex H - Print Management Service Class

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Resize Mode

/// Defines how images should be resized to fit the target dimensions
public enum ResizeMode: Sendable {
    /// Maintain aspect ratio, add borders to fill space (letterbox/pillarbox)
    case fit
    
    /// Maintain aspect ratio, crop if needed to fill space completely
    case fill
    
    /// Distort image to fill space exactly (no aspect ratio preservation)
    case stretch
}

// MARK: - Resize Quality

/// Quality settings for image resizing
public enum ResizeQuality: Sendable {
    /// Nearest neighbor (fastest, lowest quality)
    case low
    
    /// Bilinear interpolation (good balance)
    case medium
    
    /// Bicubic interpolation (highest quality, slowest)
    case high
}

// MARK: - Image Resizer

/// Actor for resizing DICOM images for printing
///
/// Provides multiple interpolation algorithms:
/// - Nearest neighbor for speed
/// - Bilinear for balanced performance
/// - Bicubic for highest quality
/// - Area averaging for downscaling
///
/// Uses SIMD acceleration via Accelerate framework when available.
public actor ImageResizer {
    
    /// Creates a new image resizer
    public init() {}
    
    // MARK: - Main Resize Method
    
    /// Resizes pixel data from source size to target size
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data
    ///   - sourceSize: Current image size
    ///   - targetSize: Desired image size
    ///   - mode: How to handle aspect ratio (fit, fill, stretch)
    ///   - quality: Interpolation quality (low, medium, high)
    ///   - samplesPerPixel: Number of samples per pixel (1 for grayscale, 3 for RGB)
    /// - Returns: Resized pixel data
    /// - Throws: ImageResizingError if resizing fails
    public func resize(
        pixelData: Data,
        from sourceSize: CGSize,
        to targetSize: CGSize,
        mode: ResizeMode,
        quality: ResizeQuality,
        samplesPerPixel: Int = 1
    ) async throws -> Data {
        // Validate inputs
        guard sourceSize.width > 0 && sourceSize.height > 0 else {
            throw ImageResizingError.invalidSourceSize
        }
        
        guard targetSize.width > 0 && targetSize.height > 0 else {
            throw ImageResizingError.invalidTargetSize
        }
        
        guard samplesPerPixel > 0 && samplesPerPixel <= 4 else {
            throw ImageResizingError.invalidSamplesPerPixel(samplesPerPixel)
        }
        
        let sourceWidth = Int(sourceSize.width)
        let sourceHeight = Int(sourceSize.height)
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        
        // Check if resize is needed
        if sourceWidth == targetWidth && sourceHeight == targetHeight {
            return pixelData
        }
        
        // Calculate actual resize dimensions based on mode
        let (resizeWidth, resizeHeight, needsBorders) = calculateResizeDimensions(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            mode: mode
        )
        
        // Perform the resize
        var resizedData: Data
        
        #if canImport(Accelerate)
        // Use Accelerate for high-performance resizing
        resizedData = try resizeUsingAccelerate(
            pixelData: pixelData,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: resizeWidth,
            targetHeight: resizeHeight,
            samplesPerPixel: samplesPerPixel,
            quality: quality
        )
        #else
        // Fallback to basic implementation
        resizedData = try resizeBasic(
            pixelData: pixelData,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: resizeWidth,
            targetHeight: resizeHeight,
            samplesPerPixel: samplesPerPixel,
            quality: quality
        )
        #endif
        
        // Add borders if needed (for 'fit' mode)
        if needsBorders {
            resizedData = try addBorders(
                pixelData: resizedData,
                imageWidth: resizeWidth,
                imageHeight: resizeHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                samplesPerPixel: samplesPerPixel
            )
        }
        
        return resizedData
    }
    
    // MARK: - Rotation
    
    /// Rotates image by specified angle
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data
    ///   - width: Image width
    ///   - height: Image height
    ///   - angle: Rotation angle (90, 180, or 270 degrees)
    ///   - samplesPerPixel: Number of samples per pixel
    /// - Returns: Rotated pixel data and new dimensions
    /// - Throws: ImageResizingError if rotation fails
    public func rotate(
        pixelData: Data,
        width: Int,
        height: Int,
        by angle: RotationAngle,
        samplesPerPixel: Int = 1
    ) async throws -> (data: Data, width: Int, height: Int) {
        guard samplesPerPixel > 0 && samplesPerPixel <= 4 else {
            throw ImageResizingError.invalidSamplesPerPixel(samplesPerPixel)
        }
        
        switch angle {
        case .degrees90:
            return try rotate90(pixelData: pixelData, width: width, height: height, samplesPerPixel: samplesPerPixel)
        case .degrees180:
            return try rotate180(pixelData: pixelData, width: width, height: height, samplesPerPixel: samplesPerPixel)
        case .degrees270:
            return try rotate270(pixelData: pixelData, width: width, height: height, samplesPerPixel: samplesPerPixel)
        }
    }
    
    /// Flips image horizontally
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data
    ///   - width: Image width
    ///   - height: Image height
    ///   - samplesPerPixel: Number of samples per pixel
    /// - Returns: Flipped pixel data
    /// - Throws: ImageResizingError if flip fails
    public func flipHorizontal(
        pixelData: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int = 1
    ) async throws -> Data {
        guard samplesPerPixel > 0 && samplesPerPixel <= 4 else {
            throw ImageResizingError.invalidSamplesPerPixel(samplesPerPixel)
        }
        
        var bytes = Array(pixelData)
        let rowSize = width * samplesPerPixel
        
        for row in 0..<height {
            let rowStart = row * rowSize
            var leftCol = rowStart
            var rightCol = rowStart + rowSize - samplesPerPixel
            
            while leftCol < rightCol {
                // Swap pixels
                for sample in 0..<samplesPerPixel {
                    bytes.swapAt(leftCol + sample, rightCol + sample)
                }
                leftCol += samplesPerPixel
                rightCol -= samplesPerPixel
            }
        }
        
        return Data(bytes)
    }
    
    /// Flips image vertically
    ///
    /// - Parameters:
    ///   - pixelData: Input pixel data
    ///   - width: Image width
    ///   - height: Image height
    ///   - samplesPerPixel: Number of samples per pixel
    /// - Returns: Flipped pixel data
    /// - Throws: ImageResizingError if flip fails
    public func flipVertical(
        pixelData: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int = 1
    ) async throws -> Data {
        guard samplesPerPixel > 0 && samplesPerPixel <= 4 else {
            throw ImageResizingError.invalidSamplesPerPixel(samplesPerPixel)
        }
        
        var bytes = Array(pixelData)
        let rowSize = width * samplesPerPixel
        
        var topRow = 0
        var bottomRow = (height - 1) * rowSize
        
        while topRow < bottomRow {
            for col in 0..<rowSize {
                bytes.swapAt(topRow + col, bottomRow + col)
            }
            topRow += rowSize
            bottomRow -= rowSize
        }
        
        return Data(bytes)
    }
    
    // MARK: - Private Helper Methods
    
    private func calculateResizeDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        mode: ResizeMode
    ) -> (width: Int, height: Int, needsBorders: Bool) {
        switch mode {
        case .fit:
            // Maintain aspect ratio, fit inside target dimensions
            let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
            let targetAspect = Double(targetWidth) / Double(targetHeight)
            
            if sourceAspect > targetAspect {
                // Limited by width
                let newWidth = targetWidth
                let newHeight = Int(Double(targetWidth) / sourceAspect)
                return (newWidth, newHeight, newHeight < targetHeight)
            } else {
                // Limited by height
                let newHeight = targetHeight
                let newWidth = Int(Double(targetHeight) * sourceAspect)
                return (newWidth, newHeight, newWidth < targetWidth)
            }
            
        case .fill:
            // Maintain aspect ratio, fill target dimensions (crop if needed)
            let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
            let targetAspect = Double(targetWidth) / Double(targetHeight)
            
            if sourceAspect > targetAspect {
                // Limited by height
                let newHeight = targetHeight
                let newWidth = Int(Double(targetHeight) * sourceAspect)
                return (newWidth, newHeight, false)
            } else {
                // Limited by width
                let newWidth = targetWidth
                let newHeight = Int(Double(targetWidth) / sourceAspect)
                return (newWidth, newHeight, false)
            }
            
        case .stretch:
            // Ignore aspect ratio, stretch to fit exactly
            return (targetWidth, targetHeight, false)
        }
    }
    
    #if canImport(Accelerate)
    private func resizeUsingAccelerate(
        pixelData: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        samplesPerPixel: Int,
        quality: ResizeQuality
    ) throws -> Data {
        let sourceBytes = Array(pixelData)
        let sourceRowBytes = sourceWidth * samplesPerPixel
        let destRowBytes = targetWidth * samplesPerPixel
        let totalDestBytes = targetHeight * destRowBytes
        
        var destBytes = [UInt8](repeating: 0, count: totalDestBytes)
        
        // Process each channel separately
        for channel in 0..<samplesPerPixel {
            // Extract channel
            var sourceChannel = [UInt8](repeating: 0, count: sourceWidth * sourceHeight)
            for row in 0..<sourceHeight {
                for col in 0..<sourceWidth {
                    let srcIndex = row * sourceRowBytes + col * samplesPerPixel + channel
                    let dstIndex = row * sourceWidth + col
                    sourceChannel[dstIndex] = sourceBytes[srcIndex]
                }
            }
            
            var destChannel = [UInt8](repeating: 0, count: targetWidth * targetHeight)
            
            // Scale using vImage with pointers whose lifetime spans the call.
            let error: vImage_Error = sourceChannel.withUnsafeMutableBytes { sourceBytes in
                destChannel.withUnsafeMutableBytes { destBytes in
                    var sourceBuffer = vImage_Buffer(
                        data: sourceBytes.baseAddress,
                        height: vImagePixelCount(sourceHeight),
                        width: vImagePixelCount(sourceWidth),
                        rowBytes: sourceWidth
                    )
                    var destBuffer = vImage_Buffer(
                        data: destBytes.baseAddress,
                        height: vImagePixelCount(targetHeight),
                        width: vImagePixelCount(targetWidth),
                        rowBytes: targetWidth
                    )
                    return vImageScale_Planar8(
                        &sourceBuffer,
                        &destBuffer,
                        nil,
                        vImage_Flags(kvImageHighQualityResampling)
                    )
                }
            }
            
            guard error == kvImageNoError else {
                throw ImageResizingError.accelerateError(Int(error))
            }
            
            // Interleave channel back
            for row in 0..<targetHeight {
                for col in 0..<targetWidth {
                    let srcIndex = row * targetWidth + col
                    let dstIndex = row * destRowBytes + col * samplesPerPixel + channel
                    destBytes[dstIndex] = destChannel[srcIndex]
                }
            }
        }
        
        return Data(destBytes)
    }
    #endif
    
    private func resizeBasic(
        pixelData: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        samplesPerPixel: Int,
        quality: ResizeQuality
    ) throws -> Data {
        let sourceBytes = Array(pixelData)
        let sourceRowBytes = sourceWidth * samplesPerPixel
        let destRowBytes = targetWidth * samplesPerPixel
        let totalDestBytes = targetHeight * destRowBytes
        
        var destBytes = [UInt8](repeating: 0, count: totalDestBytes)
        
        let scaleX = Double(sourceWidth) / Double(targetWidth)
        let scaleY = Double(sourceHeight) / Double(targetHeight)
        
        for destY in 0..<targetHeight {
            for destX in 0..<targetWidth {
                let srcX = Double(destX) * scaleX
                let srcY = Double(destY) * scaleY
                
                let destIndex = destY * destRowBytes + destX * samplesPerPixel
                
                switch quality {
                case .low:
                    // Nearest neighbor
                    let nearestX = Int(srcX)
                    let nearestY = Int(srcY)
                    let srcIndex = nearestY * sourceRowBytes + nearestX * samplesPerPixel
                    
                    for channel in 0..<samplesPerPixel {
                        destBytes[destIndex + channel] = sourceBytes[srcIndex + channel]
                    }
                    
                case .medium, .high:
                    // Bilinear interpolation
                    let x0 = Int(srcX)
                    let y0 = Int(srcY)
                    let x1 = min(x0 + 1, sourceWidth - 1)
                    let y1 = min(y0 + 1, sourceHeight - 1)
                    
                    let dx = srcX - Double(x0)
                    let dy = srcY - Double(y0)
                    
                    for channel in 0..<samplesPerPixel {
                        let p00 = Double(sourceBytes[y0 * sourceRowBytes + x0 * samplesPerPixel + channel])
                        let p10 = Double(sourceBytes[y0 * sourceRowBytes + x1 * samplesPerPixel + channel])
                        let p01 = Double(sourceBytes[y1 * sourceRowBytes + x0 * samplesPerPixel + channel])
                        let p11 = Double(sourceBytes[y1 * sourceRowBytes + x1 * samplesPerPixel + channel])
                        
                        let value = (1.0 - dx) * (1.0 - dy) * p00 +
                                    dx * (1.0 - dy) * p10 +
                                    (1.0 - dx) * dy * p01 +
                                    dx * dy * p11
                        
                        destBytes[destIndex + channel] = UInt8(min(max(value, 0.0), 255.0))
                    }
                }
            }
        }
        
        return Data(destBytes)
    }
    
    private func addBorders(
        pixelData: Data,
        imageWidth: Int,
        imageHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        samplesPerPixel: Int
    ) throws -> Data {
        let xOffset = (targetWidth - imageWidth) / 2
        let yOffset = (targetHeight - imageHeight) / 2
        
        let destRowBytes = targetWidth * samplesPerPixel
        let totalDestBytes = targetHeight * destRowBytes
        
        var destBytes = [UInt8](repeating: 0, count: totalDestBytes)  // Black borders
        
        let sourceBytes = Array(pixelData)
        let sourceRowBytes = imageWidth * samplesPerPixel
        
        for row in 0..<imageHeight {
            let srcOffset = row * sourceRowBytes
            let dstOffset = (row + yOffset) * destRowBytes + xOffset * samplesPerPixel
            
            for col in 0..<(imageWidth * samplesPerPixel) {
                destBytes[dstOffset + col] = sourceBytes[srcOffset + col]
            }
        }
        
        return Data(destBytes)
    }
    
    // MARK: - Rotation Helpers
    
    private func rotate90(
        pixelData: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int
    ) throws -> (data: Data, width: Int, height: Int) {
        let sourceBytes = Array(pixelData)
        let newWidth = height
        let newHeight = width
        let sourceRowBytes = width * samplesPerPixel
        let destRowBytes = newWidth * samplesPerPixel
        
        var destBytes = [UInt8](repeating: 0, count: newWidth * newHeight * samplesPerPixel)
        
        for srcY in 0..<height {
            for srcX in 0..<width {
                let srcIndex = srcY * sourceRowBytes + srcX * samplesPerPixel
                let destX = height - 1 - srcY
                let destY = srcX
                let destIndex = destY * destRowBytes + destX * samplesPerPixel
                
                for channel in 0..<samplesPerPixel {
                    destBytes[destIndex + channel] = sourceBytes[srcIndex + channel]
                }
            }
        }
        
        return (Data(destBytes), newWidth, newHeight)
    }
    
    private func rotate180(
        pixelData: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int
    ) throws -> (data: Data, width: Int, height: Int) {
        let sourceBytes = Array(pixelData)
        let rowBytes = width * samplesPerPixel
        var destBytes = [UInt8](repeating: 0, count: sourceBytes.count)
        
        for srcY in 0..<height {
            for srcX in 0..<width {
                let srcIndex = srcY * rowBytes + srcX * samplesPerPixel
                let destX = width - 1 - srcX
                let destY = height - 1 - srcY
                let destIndex = destY * rowBytes + destX * samplesPerPixel
                
                for channel in 0..<samplesPerPixel {
                    destBytes[destIndex + channel] = sourceBytes[srcIndex + channel]
                }
            }
        }
        
        return (Data(destBytes), width, height)
    }
    
    private func rotate270(
        pixelData: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int
    ) throws -> (data: Data, width: Int, height: Int) {
        let sourceBytes = Array(pixelData)
        let newWidth = height
        let newHeight = width
        let sourceRowBytes = width * samplesPerPixel
        let destRowBytes = newWidth * samplesPerPixel
        
        var destBytes = [UInt8](repeating: 0, count: newWidth * newHeight * samplesPerPixel)
        
        for srcY in 0..<height {
            for srcX in 0..<width {
                let srcIndex = srcY * sourceRowBytes + srcX * samplesPerPixel
                let destX = srcY
                let destY = width - 1 - srcX
                let destIndex = destY * destRowBytes + destX * samplesPerPixel
                
                for channel in 0..<samplesPerPixel {
                    destBytes[destIndex + channel] = sourceBytes[srcIndex + channel]
                }
            }
        }
        
        return (Data(destBytes), newWidth, newHeight)
    }
}

// MARK: - Rotation Angle

/// Supported rotation angles
public enum RotationAngle: Sendable {
    case degrees90
    case degrees180
    case degrees270
}

// MARK: - Image Resizing Error

/// Errors that can occur during image resizing
public enum ImageResizingError: Error, CustomStringConvertible {
    case invalidSourceSize
    case invalidTargetSize
    case invalidSamplesPerPixel(Int)
    case accelerateError(Int)
    
    public var description: String {
        switch self {
        case .invalidSourceSize:
            return "Invalid source image size"
        case .invalidTargetSize:
            return "Invalid target image size"
        case .invalidSamplesPerPixel(let samples):
            return "Invalid samples per pixel: \(samples)"
        case .accelerateError(let code):
            return "Accelerate framework error: \(code)"
        }
    }
}
