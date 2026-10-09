// NEMA-verified: 2026a, checked 2026-09-29 — 1-bit frames unpacked least-significant-bit first per PS3.5 2026a 8.1.1 and D.1; LABELMAP frames read as 8- or 16-bit unsigned cells whose value is the Segment Number per PS3.3 Table C.8.20-2 and C.8.20.2.3.3
//
// SegmentationPixelDataExtractor.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Extracts segmentation masks from DICOM segmentation pixel data
///
/// Supports binary (1-bit packed), fractional (8 or 16-bit) and LABELMAP (8 or 16-bit,
/// pixel value = Segment Number) segmentation types. Binary and fractional frames are
/// mapped to segments through the Per-Frame Functional Groups; a LABELMAP frame holds
/// every segment of one slice.
///
/// Reference: PS3.3 C.8.20.2 - Segmentation Image Module
public struct SegmentationPixelDataExtractor: Sendable {

    // MARK: - LABELMAP Extraction

    /// Extract one LABELMAP frame as Segment Numbers
    ///
    /// A LABELMAP frame is rows × columns unsigned cells of Bits Allocated 8 or 16
    /// (PS3.3 Table C.8.20-2), little-endian; each value is the Segment Number of the
    /// segment present at that pixel (C.8.20.2.3.3).
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data of all frames
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    ///   - bitsAllocated: Bits allocated per pixel (8 or 16)
    /// - Returns: The Segment Number of every pixel, or nil if the parameters are invalid
    public static func extractLabelmapFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int,
        bitsAllocated: Int
    ) -> [UInt16]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
            return nil
        }
        guard bitsAllocated == 8 || bitsAllocated == 16 else {
            return nil
        }

        let totalPixels = rows * columns
        let bytesPerPixel = bitsAllocated / 8
        let bytesPerFrame = totalPixels * bytesPerPixel
        let frameOffset = frameIndex * bytesPerFrame

        guard frameOffset + bytesPerFrame <= pixelData.count else {
            return nil
        }

        let frameData = pixelData.subdata(in: frameOffset..<(frameOffset + bytesPerFrame))
        var labels = [UInt16](repeating: 0, count: totalPixels)
        for pixelIndex in 0..<totalPixels {
            let offset = pixelIndex * bytesPerPixel
            if bitsAllocated == 8 {
                labels[pixelIndex] = UInt16(frameData[offset])
            } else {
                labels[pixelIndex] = UInt16(frameData[offset]) | (UInt16(frameData[offset + 1]) << 8)
            }
        }
        return labels
    }

    /// Extract the mask of one segment from one LABELMAP frame
    ///
    /// - Parameters:
    ///   - segmentation: The LABELMAP segmentation
    ///   - segmentNumber: The Segment Number to extract
    ///   - frameIndex: The frame (slice) to read, 0-based
    ///   - pixelData: The raw pixel data
    /// - Returns: 1 where the pixel value equals `segmentNumber`, 0 elsewhere, or nil if the
    ///   segmentation is not a LABELMAP or the frame cannot be read
    public static func extractLabelmapSegmentMask(
        from segmentation: Segmentation,
        segmentNumber: Int,
        frameIndex: Int,
        pixelData: Data
    ) -> [UInt8]? {
        guard segmentation.segmentationType == .labelmap,
              let labels = extractLabelmapFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: segmentation.rows,
                columns: segmentation.columns,
                bitsAllocated: segmentation.bitsAllocated
              ) else {
            return nil
        }
        return labels.map { Int($0) == segmentNumber ? 1 : 0 }
    }

    /// Extract every segment's mask from one LABELMAP frame
    ///
    /// - Parameters:
    ///   - segmentation: The LABELMAP segmentation
    ///   - frameIndex: The frame (slice) to read, 0-based
    ///   - pixelData: The raw pixel data
    /// - Returns: Segment Number → mask (1 present, 0 absent) for every segment of the
    ///   Segment Sequence; empty if the frame cannot be read
    public static func extractLabelmapSegmentMasks(
        from segmentation: Segmentation,
        frameIndex: Int,
        pixelData: Data
    ) -> [Int: [UInt8]] {
        guard segmentation.segmentationType == .labelmap,
              let labels = extractLabelmapFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: segmentation.rows,
                columns: segmentation.columns,
                bitsAllocated: segmentation.bitsAllocated
              ) else {
            return [:]
        }
        var masks: [Int: [UInt8]] = [:]
        for segment in segmentation.segments {
            let number = segment.segmentNumber
            masks[number] = labels.map { Int($0) == number ? 1 : 0 }
        }
        return masks
    }
    
    // MARK: - Binary Segmentation Extraction
    
    /// Extract a single binary segmentation frame from packed binary data
    ///
    /// Binary segmentations use 1 bit per pixel, packed into bytes (8 pixels per byte).
    /// Each bit represents presence (1) or absence (0) of the segment at that pixel location.
    /// Bits are packed with the most significant bit first.
    ///
    /// Reference: PS3.3 C.8.20.2 - Binary segmentation encoding
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data containing packed binary values
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    /// - Returns: Array of UInt8 values (0 or 1) representing the binary mask, or nil if invalid parameters
    public static func extractBinaryFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int
    ) -> [UInt8]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
            return nil
        }
        
        let totalPixels = rows * columns
        
        // Binary segmentation: 1 bit per pixel, packed into bytes
        // Each frame requires ceil(totalPixels / 8) bytes
        let bitsPerFrame = totalPixels
        let bytesPerFrame = (bitsPerFrame + 7) / 8  // Round up to nearest byte
        
        let frameOffset = frameIndex * bytesPerFrame
        
        guard frameOffset + bytesPerFrame <= pixelData.count else {
            return nil
        }
        
        // Extract the packed frame data
        let frameData = pixelData.subdata(in: frameOffset..<(frameOffset + bytesPerFrame))
        
        // Unpack the bits into individual pixel values
        var mask = [UInt8](repeating: 0, count: totalPixels)
        
        for pixelIndex in 0..<totalPixels {
            let byteIndex = pixelIndex / 8
            let bitIndex = pixelIndex % 8   // least significant bit first (PS3.5 8.1.1, D.1)

            if byteIndex < frameData.count {
                let byte = frameData[byteIndex]
                let bitValue = (byte >> bitIndex) & 0x01
                mask[pixelIndex] = bitValue
            }
        }
        
        return mask
    }
    
    // MARK: - Fractional Segmentation Extraction
    
    /// Extract a single fractional segmentation frame from 8 or 16-bit pixel data
    ///
    /// Fractional segmentations use 8 or 16-bit unsigned integers to represent
    /// probability or occupancy values. Values are scaled based on maxFractionalValue.
    ///
    /// Reference: PS3.3 C.8.20.2 - Fractional segmentation encoding
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data containing fractional values
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    ///   - bitsAllocated: Bits allocated per pixel (8 or 16)
    ///   - maxValue: Maximum fractional value (used for normalization)
    /// - Returns: Array of UInt8 values (0-255) normalized for rendering, or nil if invalid parameters
    public static func extractFractionalFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        maxValue: Int
    ) -> [UInt8]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
            return nil
        }
        
        guard bitsAllocated == 8 || bitsAllocated == 16 else {
            return nil
        }
        
        guard maxValue > 0 else {
            return nil
        }
        
        let totalPixels = rows * columns
        let bytesPerPixel = bitsAllocated / 8
        let bytesPerFrame = totalPixels * bytesPerPixel
        
        let frameOffset = frameIndex * bytesPerFrame
        
        guard frameOffset + bytesPerFrame <= pixelData.count else {
            return nil
        }
        
        // Extract the frame data
        let frameData = pixelData.subdata(in: frameOffset..<(frameOffset + bytesPerFrame))
        
        // Extract and normalize pixel values
        var mask = [UInt8](repeating: 0, count: totalPixels)
        let scale = 255.0 / Double(maxValue)
        
        for pixelIndex in 0..<totalPixels {
            let offset = pixelIndex * bytesPerPixel
            
            let rawValue: Int
            if bitsAllocated == 8 {
                rawValue = Int(frameData[offset])
            } else {
                // 16-bit little-endian
                let low = Int(frameData[offset])
                let high = Int(frameData[offset + 1])
                rawValue = low | (high << 8)
            }
            
            // Normalize to 0-255 range
            let normalized = min(Double(rawValue), Double(maxValue)) * scale
            mask[pixelIndex] = UInt8(max(0, min(255, normalized)))
        }
        
        return mask
    }
    
    // MARK: - Segment Mask Extraction
    
    /// Extract a specific segment mask from a segmentation object
    ///
    /// Maps frames to the requested segment number using Per-Frame Functional Groups.
    /// For binary segmentations, each frame represents a single segment.
    /// For fractional segmentations, frames may represent different segments.
    /// For a LABELMAP the first frame is read and the mask is 1 where the pixel value is
    /// the Segment Number (use ``extractLabelmapSegmentMask(from:segmentNumber:frameIndex:pixelData:)``
    /// for other slices).
    ///
    /// - Parameters:
    ///   - segmentation: The segmentation object containing metadata
    ///   - segmentNumber: The segment number to extract (1-based for BINARY/FRACTIONAL; any
    ///     described Segment Number, including 0, for LABELMAP)
    ///   - pixelData: The raw pixel data
    /// - Returns: Array of UInt8 values representing the segment mask (0-255), or nil if segment not found
    public static func extractSegmentMask(
        from segmentation: Segmentation,
        segmentNumber: Int,
        pixelData: Data
    ) -> [UInt8]? {
        if segmentation.segmentationType == .labelmap {
            guard segmentation.segments.contains(where: { $0.segmentNumber == segmentNumber }) else {
                return nil
            }
            return extractLabelmapSegmentMask(
                from: segmentation,
                segmentNumber: segmentNumber,
                frameIndex: 0,
                pixelData: pixelData
            )
        }

        guard segmentNumber > 0 && segmentNumber <= segmentation.numberOfSegments else {
            return nil
        }

        // Find all frames that belong to this segment
        var segmentFrames: [Int] = []
        
        for (frameIndex, functionalGroup) in segmentation.perFrameFunctionalGroups.enumerated() {
            if let segmentID = functionalGroup.segmentIdentification?.referencedSegmentNumber,
               segmentID == segmentNumber {
                segmentFrames.append(frameIndex)
            }
        }
        
        guard !segmentFrames.isEmpty else {
            return nil
        }
        
        // For now, extract the first frame belonging to this segment
        // In multi-frame scenarios, this would need more sophisticated handling
        let frameIndex = segmentFrames[0]
        
        switch segmentation.segmentationType {
        case .binary:
            return extractBinaryFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: segmentation.rows,
                columns: segmentation.columns
            )
            
        case .fractional:
            guard let maxValue = segmentation.maxFractionalValue else {
                return nil
            }
            
            return extractFractionalFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: segmentation.rows,
                columns: segmentation.columns,
                bitsAllocated: segmentation.bitsAllocated,
                maxValue: maxValue
            )

        case .labelmap:
            // Handled above; a LABELMAP has no per-frame Segment Identification.
            return nil
        }
    }
    
    // MARK: - All Segments Extraction
    
    /// Extract all segment masks from a segmentation object
    ///
    /// Returns a dictionary mapping segment numbers to their corresponding masks.
    /// Each mask is normalized to 0-255 for rendering purposes. For a LABELMAP the first
    /// frame is read (see ``extractLabelmapSegmentMasks(from:frameIndex:pixelData:)`` for
    /// other slices).
    ///
    /// - Parameters:
    ///   - segmentation: The segmentation object containing metadata
    ///   - pixelData: The raw pixel data
    /// - Returns: Dictionary mapping segment number to mask array, empty if extraction fails
    public static func extractAllSegmentMasks(
        from segmentation: Segmentation,
        pixelData: Data
    ) -> [Int: [UInt8]] {
        if segmentation.segmentationType == .labelmap {
            return extractLabelmapSegmentMasks(from: segmentation, frameIndex: 0, pixelData: pixelData)
        }

        var masks: [Int: [UInt8]] = [:]
        
        // Build frame-to-segment mapping
        var segmentToFrames: [Int: [Int]] = [:]
        
        for (frameIndex, functionalGroup) in segmentation.perFrameFunctionalGroups.enumerated() {
            if let segmentID = functionalGroup.segmentIdentification?.referencedSegmentNumber {
                segmentToFrames[segmentID, default: []].append(frameIndex)
            }
        }
        
        // Extract mask for each segment
        for segment in segmentation.segments {
            guard let frames = segmentToFrames[segment.segmentNumber],
                  let firstFrame = frames.first else {
                continue
            }
            
            let mask: [UInt8]?
            
            switch segmentation.segmentationType {
            case .binary:
                mask = extractBinaryFrame(
                    from: pixelData,
                    frameIndex: firstFrame,
                    rows: segmentation.rows,
                    columns: segmentation.columns
                )
                
            case .fractional:
                guard let maxValue = segmentation.maxFractionalValue else {
                    continue
                }
                
                mask = extractFractionalFrame(
                    from: pixelData,
                    frameIndex: firstFrame,
                    rows: segmentation.rows,
                    columns: segmentation.columns,
                    bitsAllocated: segmentation.bitsAllocated,
                    maxValue: maxValue
                )

            case .labelmap:
                continue // handled above
            }
            
            if let mask = mask {
                masks[segment.segmentNumber] = mask
            }
        }
        
        return masks
    }
}
