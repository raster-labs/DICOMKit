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
    ///   - sopInstanceUID: Optional SOP Instance UID of the image, used to resolve image/frame-scoped Softcopy VOI LUTs
    /// - Returns: CGImage with presentation state applied, or nil if rendering fails
    public func apply(
        to pixelData: PixelData,
        frameIndex: Int = 0,
        sopInstanceUID: String? = nil
    ) -> CGImage? {
        let descriptor = pixelData.descriptor
        
        guard descriptor.photometricInterpretation.isMonochrome else {
            // Grayscale presentation states only apply to monochrome images
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
        let effectiveVOI = presentationState.effectiveVOILUT(
            forImage: sopInstanceUID,
            frameNumber: frameIndex + 1
        )
        let pipeline = GrayscaleDisplayPipeline(
            modalityLUT: presentationState.modalityLUT,
            voiLUT: effectiveVOI,
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

    // MARK: - Static Applicator Overloads (GSPS, CSPS, Pseudo-CSPS)

    /// Applies a `GrayscalePresentationState` (GSPS) to monochrome pixel data.
    public static func apply(
        _ state: GrayscalePresentationState,
        to pixelData: PixelData,
        frameIndex: Int = 0,
        sopInstanceUID: String? = nil
    ) -> CGImage? {
        PresentationStateApplicator(presentationState: state)
            .apply(to: pixelData, frameIndex: frameIndex, sopInstanceUID: sopInstanceUID)
    }

    /// Applies a `PseudoColorPresentationState` (Pseudo-CSPS, PS3.3 A.33.3 / PS3.4 N.2) to monochrome pixel data.
    ///
    /// Pipeline:
    /// 1. Modality LUT -> Effective Softcopy VOI LUT -> normalized index
    /// 2. Palette Color Lookup Table mapping to RGB
    /// 3. Display Shutters with `ShutterPresentationColorCIELabValue (0018,1624)`
    /// 4. Spatial Transformation (clockwise rotation then horizontal flip)
    /// 5. Output rendered with the state's ICC Profile (or sRGB)
    public static func apply(
        _ state: PseudoColorPresentationState,
        to pixelData: PixelData,
        frameIndex: Int = 0,
        sopInstanceUID: String? = nil
    ) -> CGImage? {
        let descriptor = pixelData.descriptor
        guard descriptor.photometricInterpretation.isMonochrome,
              let frameData = pixelData.frameData(at: frameIndex) else {
            return nil
        }

        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        guard width > 0, height > 0 else { return nil }

        let effectiveVOI = state.effectiveVOILUT(
            forImage: sopInstanceUID,
            frameNumber: frameIndex + 1
        )
        let pipeline = GrayscaleDisplayPipeline(
            modalityLUT: state.modalityLUT,
            voiLUT: effectiveVOI,
            presentationLUT: .identity
        )
        let lut = state.paletteColorLUT
        let entryCount = max(1, lut.redDescriptor.numberOfEntries)
        let firstMapped = lut.redDescriptor.firstMappedValue

        var rgbaBytes = [UInt8](repeating: 255, count: totalPixels * 4)
        let bytesPerSample = descriptor.bytesPerSample

        frameData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<totalPixels {
                let offset = i * bytesPerSample
                guard offset + bytesPerSample <= bytes.count else { break }
                let stored = descriptor.storedValue(fromCell: descriptor.cellValue(in: bytes, at: offset))
                // PS3.4 N.2: VOI LUT output is scaled across the Palette Color LUT input range
                let displayByte = Int(pipeline.displayByte(forStoredValue: stored, descriptor: descriptor))
                let mappedValue: Int
                if entryCount == 256 && firstMapped == 0 {
                    mappedValue = displayByte
                } else {
                    mappedValue = firstMapped + (displayByte * (entryCount - 1)) / 255
                }
                let color = lut.lookup(mappedValue)
                let dst = i * 4
                rgbaBytes[dst] = color.red
                rgbaBytes[dst + 1] = color.green
                rgbaBytes[dst + 2] = color.blue
                rgbaBytes[dst + 3] = 255
            }
        }

        if !state.shutters.isEmpty {
            applyColorShutters(
                shutters: state.shutters,
                shutterColor: state.shutterPresentationColor,
                to: &rgbaBytes,
                width: width,
                height: height
            )
        }

        var finalWidth = width
        var finalHeight = height
        if let spatial = state.spatialTransformation, spatial.hasTransformation {
            (rgbaBytes, finalWidth, finalHeight) = applyRGBASpatialTransformation(
                to: rgbaBytes,
                width: width,
                height: height,
                transform: spatial
            )
        }

        return createRGBACGImage(
            from: rgbaBytes,
            width: finalWidth,
            height: finalHeight,
            iccProfile: state.iccProfile
        )
    }

    /// Applies a `ColorPresentationState` (CSPS, PS3.3 A.33.2 / PS3.4 N.2) to color pixel data.
    ///
    /// Pipeline:
    /// 1. Color sample extraction (RGB / PALETTE COLOR)
    /// 2. Display Shutters with `ShutterPresentationColorCIELabValue (0018,1624)`
    /// 3. Spatial Transformation (clockwise rotation then horizontal flip)
    /// 4. Output rendered with the state's ICC Profile (or sRGB)
    public static func apply(
        _ state: ColorPresentationState,
        to pixelData: PixelData,
        frameIndex: Int = 0
    ) -> CGImage? {
        let descriptor = pixelData.descriptor
        guard !descriptor.photometricInterpretation.isMonochrome else {
            return nil
        }

        let width = descriptor.columns
        let height = descriptor.rows
        let totalPixels = width * height
        guard width > 0, height > 0 else { return nil }

        var rgbaBytes = [UInt8](repeating: 255, count: totalPixels * 4)
        for y in 0..<height {
            for x in 0..<width {
                guard let rgb = pixelData.colorValue(row: y, column: x, frame: frameIndex) else {
                    return nil
                }
                let dst = (y * width + x) * 4
                rgbaBytes[dst] = UInt8(clamping: rgb.red)
                rgbaBytes[dst + 1] = UInt8(clamping: rgb.green)
                rgbaBytes[dst + 2] = UInt8(clamping: rgb.blue)
                rgbaBytes[dst + 3] = 255
            }
        }

        if !state.shutters.isEmpty {
            applyColorShutters(
                shutters: state.shutters,
                shutterColor: state.shutterPresentationColor,
                to: &rgbaBytes,
                width: width,
                height: height
            )
        }

        var finalWidth = width
        var finalHeight = height
        if let spatial = state.spatialTransformation, spatial.hasTransformation {
            (rgbaBytes, finalWidth, finalHeight) = applyRGBASpatialTransformation(
                to: rgbaBytes,
                width: width,
                height: height,
                transform: spatial
            )
        }

        return createRGBACGImage(
            from: rgbaBytes,
            width: finalWidth,
            height: finalHeight,
            iccProfile: state.iccProfile
        )
    }

    /// Applies a `BlendingPresentationState` (PS3.3 A.33.4 / PS3.4 N.2.4) to underlay and overlay pixel data.
    ///
    /// Pipeline:
    /// 1. Underlay monochrome pipeline (`underlayModalityLUT` -> `underlayVOILUT` -> grayscale RGB)
    /// 2. Overlay monochrome pipeline (`overlayModalityLUT` -> `overlayVOILUT` -> `PaletteColorLUT`)
    /// 3. Alpha blending with `RelativeOpacity (0070,0403)`: `(1 - α) * underlay + α * overlay`
    /// 4. Display Shutters and Spatial Transformation
    public static func apply(
        _ state: BlendingPresentationState,
        underlayPixelData: PixelData,
        overlayPixelData: PixelData,
        underlayFrameIndex: Int = 0,
        overlayFrameIndex: Int = 0
    ) -> CGImage? {
        let uDesc = underlayPixelData.descriptor
        let oDesc = overlayPixelData.descriptor
        guard uDesc.photometricInterpretation.isMonochrome,
              oDesc.photometricInterpretation.isMonochrome,
              let uFrame = underlayPixelData.frameData(at: underlayFrameIndex),
              let oFrame = overlayPixelData.frameData(at: overlayFrameIndex) else {
            return nil
        }

        let width = uDesc.columns
        let height = uDesc.rows
        let totalPixels = width * height
        guard width > 0, height > 0, oDesc.columns > 0, oDesc.rows > 0 else { return nil }

        let uPipeline = GrayscaleDisplayPipeline(
            modalityLUT: state.underlayModalityLUT,
            voiLUT: state.underlayVOILUT,
            presentationLUT: .identity
        )
        let oPipeline = GrayscaleDisplayPipeline(
            modalityLUT: state.overlayModalityLUT,
            voiLUT: state.overlayVOILUT,
            presentationLUT: .identity
        )
        let lut = state.paletteColorLUT ?? PseudoColorPalette.hotIron.paletteColorLUT()
        let entryCount = max(1, lut.redDescriptor.numberOfEntries)
        let firstMapped = lut.redDescriptor.firstMappedValue
        let alpha = max(0.0, min(1.0, state.relativeOpacity))
        let oneMinusAlpha = 1.0 - alpha

        var rgbaBytes = [UInt8](repeating: 255, count: totalPixels * 4)
        let uBps = uDesc.bytesPerSample
        let oBps = oDesc.bytesPerSample

        uFrame.withUnsafeBytes { (uBytes: UnsafeRawBufferPointer) in
            oFrame.withUnsafeBytes { (oBytes: UnsafeRawBufferPointer) in
                for y in 0..<height {
                    let oY = min(oDesc.rows - 1, (y * oDesc.rows) / height)
                    for x in 0..<width {
                        let oX = min(oDesc.columns - 1, (x * oDesc.columns) / width)
                        let uIndex = y * width + x
                        let oIndex = oY * oDesc.columns + oX
                        let uOffset = uIndex * uBps
                        let oOffset = oIndex * oBps
                        guard uOffset + uBps <= uBytes.count,
                              oOffset + oBps <= oBytes.count else { continue }

                        let uStored = uDesc.storedValue(fromCell: uDesc.cellValue(in: uBytes, at: uOffset))
                        let uGray = Double(uPipeline.displayByte(forStoredValue: uStored, descriptor: uDesc))

                        let oStored = oDesc.storedValue(fromCell: oDesc.cellValue(in: oBytes, at: oOffset))
                        let oByte = Int(oPipeline.displayByte(forStoredValue: oStored, descriptor: oDesc))
                        let mappedValue: Int
                        if entryCount == 256 && firstMapped == 0 {
                            mappedValue = oByte
                        } else {
                            mappedValue = firstMapped + (oByte * (entryCount - 1)) / 255
                        }
                        let oColor = lut.lookup(mappedValue)

                        let r = UInt8(clamping: Int((oneMinusAlpha * uGray + alpha * Double(oColor.red)).rounded()))
                        let g = UInt8(clamping: Int((oneMinusAlpha * uGray + alpha * Double(oColor.green)).rounded()))
                        let b = UInt8(clamping: Int((oneMinusAlpha * uGray + alpha * Double(oColor.blue)).rounded()))

                        let dst = uIndex * 4
                        rgbaBytes[dst] = r
                        rgbaBytes[dst + 1] = g
                        rgbaBytes[dst + 2] = b
                        rgbaBytes[dst + 3] = 255
                    }
                }
            }
        }

        if !state.shutters.isEmpty {
            applyColorShutters(
                shutters: state.shutters,
                shutterColor: state.shutterPresentationColor,
                to: &rgbaBytes,
                width: width,
                height: height
            )
        }

        var finalWidth = width
        var finalHeight = height
        if let spatial = state.spatialTransformation, spatial.hasTransformation {
            (rgbaBytes, finalWidth, finalHeight) = applyRGBASpatialTransformation(
                to: rgbaBytes,
                width: width,
                height: height,
                transform: spatial
            )
        }

        return createRGBACGImage(
            from: rgbaBytes,
            width: finalWidth,
            height: finalHeight,
            iccProfile: state.iccProfile
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

    // MARK: - Color & Pseudo-Color Helpers

    private static func applyColorShutters(
        shutters: [DisplayShutter],
        shutterColor: CIELabColor?,
        to rgbaBytes: inout [UInt8],
        width: Int,
        height: Int
    ) {
        let shapes = shutters.filter {
            if case .bitmap = $0 { return false }
            return true
        }
        guard !shapes.isEmpty else { return }

        let sRGB = (shutterColor ?? .shutterBlack).sRGB
        let fillR = UInt8(max(0, min(255, Int((sRGB.red * 255).rounded()))))
        let fillG = UInt8(max(0, min(255, Int((sRGB.green * 255).rounded()))))
        let fillB = UInt8(max(0, min(255, Int((sRGB.blue * 255).rounded()))))

        for y in 0..<height {
            for x in 0..<width {
                let visible = shapes.allSatisfy { $0.contains(column: x + 1, row: y + 1) }
                if !visible {
                    let dst = (y * width + x) * 4
                    rgbaBytes[dst] = fillR
                    rgbaBytes[dst + 1] = fillG
                    rgbaBytes[dst + 2] = fillB
                    rgbaBytes[dst + 3] = 255
                }
            }
        }
    }

    private static func applyRGBASpatialTransformation(
        to rgbaBytes: [UInt8],
        width: Int,
        height: Int,
        transform: SpatialTransformation
    ) -> ([UInt8], Int, Int) {
        var current = rgbaBytes
        var currentWidth = width
        var currentHeight = height

        if transform.isRotated {
            switch transform.rotation {
            case 90:
                var rotated = [UInt8](repeating: 255, count: current.count)
                for y in 0..<currentHeight {
                    for x in 0..<currentWidth {
                        let src = (y * currentWidth + x) * 4
                        let dstX = currentHeight - 1 - y
                        let dstY = x
                        let dst = (dstY * currentHeight + dstX) * 4
                        rotated[dst] = current[src]
                        rotated[dst + 1] = current[src + 1]
                        rotated[dst + 2] = current[src + 2]
                        rotated[dst + 3] = current[src + 3]
                    }
                }
                current = rotated
                swap(&currentWidth, &currentHeight)
            case 180:
                var rotated = [UInt8](repeating: 255, count: current.count)
                let totalPixels = currentWidth * currentHeight
                for i in 0..<totalPixels {
                    let src = i * 4
                    let dst = (totalPixels - 1 - i) * 4
                    rotated[dst] = current[src]
                    rotated[dst + 1] = current[src + 1]
                    rotated[dst + 2] = current[src + 2]
                    rotated[dst + 3] = current[src + 3]
                }
                current = rotated
            case 270:
                var rotated = [UInt8](repeating: 255, count: current.count)
                for y in 0..<currentHeight {
                    for x in 0..<currentWidth {
                        let src = (y * currentWidth + x) * 4
                        let dstX = y
                        let dstY = currentWidth - 1 - x
                        let dst = (dstY * currentHeight + dstX) * 4
                        rotated[dst] = current[src]
                        rotated[dst + 1] = current[src + 1]
                        rotated[dst + 2] = current[src + 2]
                        rotated[dst + 3] = current[src + 3]
                    }
                }
                current = rotated
                swap(&currentWidth, &currentHeight)
            default:
                break
            }
        }

        if transform.isFlipped {
            var flipped = [UInt8](repeating: 255, count: current.count)
            for y in 0..<currentHeight {
                for x in 0..<currentWidth {
                    let src = (y * currentWidth + x) * 4
                    let dst = (y * currentWidth + (currentWidth - 1 - x)) * 4
                    flipped[dst] = current[src]
                    flipped[dst + 1] = current[src + 1]
                    flipped[dst + 2] = current[src + 2]
                    flipped[dst + 3] = current[src + 3]
                }
            }
            current = flipped
        }

        return (current, currentWidth, currentHeight)
    }

    private static func createRGBACGImage(
        from rgbaBytes: [UInt8],
        width: Int,
        height: Int,
        iccProfile: ICCProfile?
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace: CGColorSpace
        if let profileData = iccProfile?.profileData,
           let iccSpace = CGColorSpace(iccData: profileData as CFData),
           iccSpace.numberOfComponents == 3 {
            colorSpace = iccSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: Data(rgbaBytes) as CFData) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
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
