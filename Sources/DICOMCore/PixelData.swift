import Foundation

/// DICOM Pixel Data
///
/// Represents uncompressed pixel data extracted from a DICOM file.
/// Reference: DICOM PS3.5 Section 8.2 - Native Pixel Data Format
///
/// NEMA-verified: 2026a, checked 2026-09-25 — sample extraction (little-endian Pixel Cells, High Bit / Bits Stored masking, two's-complement sign extension, Planar Configuration 0/1 layouts) matches PS3.5 2026a §8.1.1 and §8.2 and PS3.3 2026a C.7.6.3.1.3.
public struct PixelData: Sendable {
    /// The raw pixel data bytes
    public let data: Data
    
    /// Descriptor containing pixel data attributes
    public let descriptor: PixelDataDescriptor

    /// Page-aligned backing for ``data``, when it has one.
    ///
    /// Non-nil only for pixel data produced by ``pageAligned()``. Its presence is
    /// what lets a Metal renderer read these bytes without copying them; every CPU
    /// consumer goes on using ``data`` and neither knows nor cares.
    /// See `GPU_RENDERING_PLAN.md` M2b.
    public let alignedStorage: AlignedPixelBuffer?

    /// Creates a new PixelData instance
    /// - Parameters:
    ///   - data: Raw pixel data bytes
    ///   - descriptor: Pixel data descriptor
    public init(data: Data, descriptor: PixelDataDescriptor) {
        self.data = data
        self.descriptor = descriptor
        self.alignedStorage = nil
    }

    /// Creates pixel data backed by page-aligned storage.
    ///
    /// ``data`` is a no-copy view of `alignedStorage`, so the CPU and the GPU read
    /// the same bytes.
    public init(alignedStorage: AlignedPixelBuffer, descriptor: PixelDataDescriptor) {
        self.data = alignedStorage.data
        self.descriptor = descriptor
        self.alignedStorage = alignedStorage
    }
    
    // MARK: - Frame Access
    
    /// Returns the raw bytes for a specific frame
    /// - Parameter frameIndex: Zero-based frame index
    /// - Returns: Data for the specified frame, or nil if index is out of bounds
    public func frameData(at frameIndex: Int) -> Data? {
        guard frameIndex >= 0 && frameIndex < descriptor.numberOfFrames else {
            return nil
        }
        
        let startOffset = frameIndex * descriptor.bytesPerFrame
        let endOffset = startOffset + descriptor.bytesPerFrame
        
        guard endOffset <= data.count else {
            return nil
        }
        
        // Create a fresh Data copy to ensure indices start at 0
        return Data(data[startOffset..<endOffset])
    }
    
    /// Returns pixel values for a specific frame as an array of integers
    /// - Parameter frameIndex: Zero-based frame index
    /// - Returns: Array of pixel values, or nil if extraction fails
    public func pixelValues(forFrame frameIndex: Int) -> [Int]? {
        guard let frameData = frameData(at: frameIndex) else {
            return nil
        }
        
        return extractPixelValues(from: frameData)
    }
    
    /// Returns all pixel values for all frames
    /// - Returns: 2D array where each inner array contains pixel values for one frame
    public func allPixelValues() -> [[Int]]? {
        var result: [[Int]] = []
        for frameIndex in 0..<descriptor.numberOfFrames {
            guard let values = pixelValues(forFrame: frameIndex) else {
                return nil
            }
            result.append(values)
        }
        return result
    }
    
    // MARK: - Single Pixel Access
    
    /// Returns the pixel value at a specific location
    /// - Parameters:
    ///   - row: Row index (0-based)
    ///   - column: Column index (0-based)
    ///   - frameIndex: Frame index (0-based, default 0)
    /// - Returns: Pixel value, or nil if coordinates are out of bounds
    public func pixelValue(row: Int, column: Int, frame frameIndex: Int = 0) -> Int? {
        guard row >= 0 && row < descriptor.rows &&
              column >= 0 && column < descriptor.columns &&
              frameIndex >= 0 && frameIndex < descriptor.numberOfFrames else {
            return nil
        }
        
        // For monochrome images
        if descriptor.samplesPerPixel == 1 {
            let pixelIndex = row * descriptor.columns + column
            let frameOffset = frameIndex * descriptor.bytesPerFrame
            let offset = frameOffset + pixelIndex * descriptor.bytesPerSample
            return readPixelValue(at: offset)
        }
        
        // For color images (return first sample, use colorValue for full RGB)
        let pixelIndex = row * descriptor.columns + column
        return readColorPixelValue(at: pixelIndex, frame: frameIndex, sample: 0)
    }
    
    /// Returns the RGB color value at a specific location for color images
    /// - Parameters:
    ///   - row: Row index (0-based)
    ///   - column: Column index (0-based)
    ///   - frameIndex: Frame index (0-based, default 0)
    /// - Returns: Tuple of (red, green, blue) values, or nil if not a color image or out of bounds
    public func colorValue(row: Int, column: Int, frame frameIndex: Int = 0) -> (red: Int, green: Int, blue: Int)? {
        guard descriptor.samplesPerPixel == 3 else {
            return nil
        }
        
        guard row >= 0 && row < descriptor.rows &&
              column >= 0 && column < descriptor.columns &&
              frameIndex >= 0 && frameIndex < descriptor.numberOfFrames else {
            return nil
        }
        
        let pixelIndex = row * descriptor.columns + column
        
        guard let r = readColorPixelValue(at: pixelIndex, frame: frameIndex, sample: 0),
              let g = readColorPixelValue(at: pixelIndex, frame: frameIndex, sample: 1),
              let b = readColorPixelValue(at: pixelIndex, frame: frameIndex, sample: 2) else {
            return nil
        }
        
        return (red: r, green: g, blue: b)
    }
    
    // MARK: - Statistics
    
    /// Calculates the minimum and maximum pixel values in the specified frame
    /// - Parameter frameIndex: Frame index (default 0)
    /// - Returns: Tuple of (min, max) values, or nil if calculation fails
    public func pixelRange(forFrame frameIndex: Int = 0) -> (min: Int, max: Int)? {
        guard let values = pixelValues(forFrame: frameIndex), !values.isEmpty else {
            return nil
        }
        
        var minVal = values[0]
        var maxVal = values[0]
        
        for value in values {
            if value < minVal { minVal = value }
            if value > maxVal { maxVal = value }
        }
        
        return (min: minVal, max: maxVal)
    }
    
    // MARK: - Private Helpers
    
    /// Extracts all pixel values from frame data
    private func extractPixelValues(from frameData: Data) -> [Int] {
        var values: [Int] = []
        values.reserveCapacity(descriptor.pixelsPerFrame * descriptor.samplesPerPixel)
        
        if descriptor.samplesPerPixel == 1 {
            // Monochrome image
            for i in stride(from: 0, to: frameData.count, by: descriptor.bytesPerSample) {
                if let value = readPixelValueFromFrameData(frameData, at: i) {
                    values.append(value)
                }
            }
        } else {
            // Color image - extract all samples
            for pixelIndex in 0..<descriptor.pixelsPerFrame {
                for sample in 0..<descriptor.samplesPerPixel {
                    if let value = readColorPixelValueFromFrameData(frameData, pixelIndex: pixelIndex, sample: sample) {
                        values.append(value)
                    }
                }
            }
        }
        
        return values
    }
    
    /// Reads a single pixel value from the main data buffer
    private func readPixelValue(at offset: Int) -> Int? {
        guard offset + descriptor.bytesPerSample <= data.count else {
            return nil
        }
        
        return readRawValue(from: data, at: offset)
    }
    
    /// Reads a pixel value from frame-specific data
    private func readPixelValueFromFrameData(_ frameData: Data, at offset: Int) -> Int? {
        guard offset + descriptor.bytesPerSample <= frameData.count else {
            return nil
        }
        
        return readRawValue(from: frameData, at: offset)
    }
    
    /// Reads a color sample value for a specific pixel and sample
    private func readColorPixelValue(at pixelIndex: Int, frame: Int, sample: Int) -> Int? {
        let frameOffset = frame * descriptor.bytesPerFrame
        let offset: Int
        
        if descriptor.planarConfiguration == 0 {
            // Color-by-pixel: R1G1B1R2G2B2...
            offset = frameOffset + (pixelIndex * descriptor.samplesPerPixel + sample) * descriptor.bytesPerSample
        } else {
            // Color-by-plane: R1R2...G1G2...B1B2...
            let planeSize = descriptor.pixelsPerFrame * descriptor.bytesPerSample
            offset = frameOffset + sample * planeSize + pixelIndex * descriptor.bytesPerSample
        }
        
        return readPixelValue(at: offset)
    }
    
    /// Reads a color sample value from frame-specific data
    private func readColorPixelValueFromFrameData(_ frameData: Data, pixelIndex: Int, sample: Int) -> Int? {
        let offset: Int
        
        if descriptor.planarConfiguration == 0 {
            // Color-by-pixel: R1G1B1R2G2B2...
            offset = (pixelIndex * descriptor.samplesPerPixel + sample) * descriptor.bytesPerSample
        } else {
            // Color-by-plane: R1R2...G1G2...B1B2...
            let planeSize = descriptor.pixelsPerFrame * descriptor.bytesPerSample
            offset = sample * planeSize + pixelIndex * descriptor.bytesPerSample
        }
        
        return readPixelValueFromFrameData(frameData, at: offset)
    }
    
    /// Reads raw value from data buffer and applies bit masking
    private func readRawValue(from buffer: Data, at offset: Int) -> Int {
        let rawValue: Int
        
        if descriptor.bytesPerSample == 1 {
            rawValue = Int(buffer[offset])
        } else if descriptor.bytesPerSample == 2 {
            let low = Int(buffer[offset])
            let high = Int(buffer[offset + 1])
            rawValue = low | (high << 8)
        } else {
            // 4 bytes
            let b0 = Int(buffer[offset])
            let b1 = Int(buffer[offset + 1])
            let b2 = Int(buffer[offset + 2])
            let b3 = Int(buffer[offset + 3])
            rawValue = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }
        
        // Apply bit masking based on bits stored and high bit
        let shiftedValue = rawValue >> descriptor.bitShift
        let maskedValue = shiftedValue & descriptor.storedBitMask
        
        // Apply sign extension if needed
        if descriptor.isSigned {
            let signBit = 1 << (descriptor.bitsStored - 1)
            if maskedValue & signBit != 0 {
                return maskedValue - (1 << descriptor.bitsStored)
            }
        }
        
        return maskedValue
    }
}
