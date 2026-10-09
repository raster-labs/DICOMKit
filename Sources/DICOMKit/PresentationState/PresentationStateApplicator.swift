// NEMA-verified: 2026a, checked 2026-09-30 — the value chain is GrayscaleDisplayPipeline (PS3.4 2026a N.2); cells are read Bits Allocated wide (PS3.5 8.1.1, D67) and quantised by WindowLUT.displayByte (D63)
// NEMA-verified: 2026a, checked 2026-09-29 — PS3.4 2026a N.2 pipeline: shutters mask outside every shape before the C.10.6 rotate-then-flip transform; the no-VOI range follows C.11.6.1
//
// PresentationStateApplicator.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-04.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

#if canImport(CoreGraphics)
import CoreGraphics

/// Applies a presentation state to DICOM pixel data for display
///
/// Applies these steps of the PS3.4 N.2 pipeline:
/// 1. Modality LUT (stored pixels → modality values)
/// 2. VOI LUT (modality values → values of interest)
/// 3. Presentation LUT (values of interest → P-Values for display)
/// 4. Display shutters (pixels outside every shutter shape are set to the
///    Shutter Presentation Value), in image coordinates
/// 5. Spatial transformation (rotation, then horizontal flip)
///
/// Displayed area selection and graphic annotations are not applied; the
/// returned image is the whole transformed frame.
///
/// Reference: PS3.3 Section A.33.1 - Grayscale Softcopy Presentation State IOD; PS3.4 N.2
public struct PresentationStateApplicator: Sendable {
    /// The presentation state to apply
    public let presentationState: GrayscalePresentationState
    
    /// Creates a new presentation state applicator
    ///
    /// - Parameter presentationState: The presentation state to apply
    public init(presentationState: GrayscalePresentationState) {
        self.presentationState = presentationState
    }
    
    // MARK: - Apply Presentation State to Pixel Data
    
    /// Applies the presentation state to pixel data and renders it to a CGImage
    ///
    /// - Parameters:
    ///   - pixelData: The pixel data to render
    ///   - frameIndex: The frame index to render (default 0)
    /// - Returns: CGImage with presentation state applied, or nil if rendering fails
    public func apply(to pixelData: PixelData, frameIndex: Int = 0) -> CGImage? {
        let descriptor = pixelData.descriptor
        
        guard descriptor.photometricInterpretation.isMonochrome else {
            // Presentation states only apply to monochrome images
            return nil
        }
        
        guard let frameData = pixelData.frameData(at: frameIndex) else {
            return nil
        }
        
        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        
        // Create output buffer
        var outputBytes = [UInt8](repeating: 0, count: totalPixels)
        
        // The PS3.4 N.2 chain of this presentation state, shared with the exporter and
        // the renderers (GrayscaleDisplayPipeline). Cells are read Bits Allocated wide
        // (PS3.5 8.1.1, D67), then shifted, masked and sign-extended.
        let pipeline = GrayscaleDisplayPipeline(
            modalityLUT: presentationState.modalityLUT,
            voiLUT: presentationState.voiLUT,
            presentationLUT: presentationState.presentationLUT)
        let bytesPerSample = descriptor.bytesPerSample
        frameData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<totalPixels {
                let offset = i * bytesPerSample
                guard offset + bytesPerSample <= bytes.count else { break }
                let stored = descriptor.storedValue(fromCell: descriptor.cellValue(in: bytes, at: offset))
                outputBytes[i] = pipeline.displayByte(forStoredValue: stored, descriptor: descriptor)
            }
        }

        // Shutters are defined in the image's own row/column coordinates
        // (C.7.6.11), so they are applied before the spatial transformation.
        if !presentationState.shutters.isEmpty {
            applyShutters(to: &outputBytes, width: width, height: height)
        }

        if let spatialTransform = presentationState.spatialTransformation, spatialTransform.hasTransformation {
            outputBytes = applySpatialTransformation(
                to: outputBytes,
                width: width,
                height: height,
                transform: spatialTransform
            )
        }
        
        // Determine final dimensions based on spatial transformation
        let (finalWidth, finalHeight) = getFinalDimensions(width: width, height: height)
        
        // Create CGImage from output buffer
        return createCGImage(
            from: outputBytes,
            width: finalWidth,
            height: finalHeight
        )
    }
    
    // MARK: - Spatial Transformation
    
    private func applySpatialTransformation(
        to bytes: [UInt8],
        width: Int,
        height: Int,
        transform: SpatialTransformation
    ) -> [UInt8] {
        var result = bytes
        var (currentWidth, currentHeight) = (width, height)

        // C.10.6: Image Rotation is applied before any Image Horizontal Flip
        if transform.isRotated {
            result = applyRotation(to: result, width: currentWidth, height: currentHeight, degrees: transform.rotation)
            if transform.rotation == 90 || transform.rotation == 270 {
                swap(&currentWidth, &currentHeight)
            }
        }

        if transform.isFlipped {
            result = applyHorizontalFlip(to: result, width: currentWidth, height: currentHeight)
        }

        return result
    }
    
    private func applyHorizontalFlip(to bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        var flipped = [UInt8](repeating: 0, count: bytes.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = y * width + (width - 1 - x)
                flipped[dstIndex] = bytes[srcIndex]
            }
        }
        
        return flipped
    }
    
    private func applyRotation(
        to bytes: [UInt8],
        width: Int,
        height: Int,
        degrees: Int
    ) -> [UInt8] {
        switch degrees {
        case 90:
            return rotateBy90(bytes: bytes, width: width, height: height)
        case 180:
            return rotateBy180(bytes: bytes, width: width, height: height)
        case 270:
            return rotateBy270(bytes: bytes, width: width, height: height)
        default:
            return bytes
        }
    }
    
    private func rotateBy90(bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        var rotated = [UInt8](repeating: 0, count: bytes.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstX = height - 1 - y
                let dstY = x
                let dstIndex = dstY * height + dstX
                rotated[dstIndex] = bytes[srcIndex]
            }
        }
        
        return rotated
    }
    
    private func rotateBy180(bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        var rotated = [UInt8](repeating: 0, count: bytes.count)
        
        for i in 0..<bytes.count {
            rotated[bytes.count - 1 - i] = bytes[i]
        }
        
        return rotated
    }
    
    private func rotateBy270(bytes: [UInt8], width: Int, height: Int) -> [UInt8] {
        var rotated = [UInt8](repeating: 0, count: bytes.count)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstX = y
                let dstY = width - 1 - x
                let dstIndex = dstY * height + dstX
                rotated[dstIndex] = bytes[srcIndex]
            }
        }
        
        return rotated
    }
    
    private func getFinalDimensions(width: Int, height: Int) -> (Int, Int) {
        guard let transform = presentationState.spatialTransformation else {
            return (width, height)
        }
        
        switch transform.rotation {
        case 90, 270:
            return (height, width)  // Swap dimensions for 90/270 degree rotation
        default:
            return (width, height)
        }
    }
    
    // MARK: - Shutters
    
    /// C.7.6.11: a shutter neutralises the pixels *outside* its shape; with several
    /// shapes "the least amount of image remaining shall be visible", i.e. only pixels
    /// inside every shape stay. Coordinates are row/column with origin 1,1, and the
    /// Shutter Presentation Value is a 16-bit P-Value (C.11.12), scaled to 8 bits here.
    private func applyShutters(to bytes: inout [UInt8], width: Int, height: Int) {
        let shapes = presentationState.shutters.filter {
            if case .bitmap = $0 { return false }   // needs the overlay plane (C.7.6.15)
            return true
        }
        guard !shapes.isEmpty else { return }

        let pValue = presentationState.shutters.first?.presentationValue ?? 0
        let fill = UInt8(max(0, min(255, (pValue * 255 + 32767) / 65535)))

        for y in 0..<height {
            for x in 0..<width {
                let visible = shapes.allSatisfy { $0.contains(column: x + 1, row: y + 1) }
                if !visible {
                    bytes[y * width + x] = fill
                }
            }
        }
    }
    
    // MARK: - CGImage Creation
    
    private func createCGImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else {
            return nil
        }
        
        let bytesPerRow = width
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

#endif // canImport(CoreGraphics)
