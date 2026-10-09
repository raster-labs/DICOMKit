// NEMA-verified: 2026a, checked 2026-09-29 — float pixel data per PS3.5 2026a 8.1.1 (findings recorded)
//
// ParametricMapPixelDataExtractor.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-05.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore

/// Extracts parametric values from DICOM Parametric Map pixel data
///
/// Supports integer (8, 16-bit), float (32-bit), and double (64-bit) pixel data formats.
/// Applies Real World Value Mapping to convert stored pixel values to physical quantities.
///
/// Reference: PS3.3 C.8.23 - Parametric Map Image Module
/// Reference: PS3.3 C.7.6.16.2.11 - Real World Value Mapping
public struct ParametricMapPixelDataExtractor: Sendable {
    
    // MARK: - Integer Pixel Data Extraction
    
    /// Extract parametric values from integer pixel data with real world value mapping
    ///
    /// Extracts stored integer pixel values and applies Real World Value Mapping
    /// to convert them to physical quantities.
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    ///   - bitsAllocated: Bits allocated per pixel (8 or 16)
    ///   - pixelRepresentation: 0 = unsigned, 1 = signed
    ///   - mapping: Real World Value Mapping to apply
    /// - Returns: Array of Double values representing physical quantities
    public static func extractIntegerFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        pixelRepresentation: Int,
        mapping: RealWorldValueMapping
    ) -> [Double]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
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
        
        // Extract integer values based on bits allocated and pixel representation
        let storedValues: [Double]
        
        if bitsAllocated == 8 {
            if pixelRepresentation == 0 {
                // Unsigned 8-bit
                storedValues = frameData.map { Double($0) }
            } else {
                // Signed 8-bit
                storedValues = frameData.map { Double(Int8(bitPattern: $0)) }
            }
        } else if bitsAllocated == 16 {
            if pixelRepresentation == 0 {
                // Unsigned 16-bit
                storedValues = stride(from: 0, to: frameData.count, by: 2).map { offset in
                    let value = frameData.withUnsafeBytes { bytes in
                        bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
                    }
                    return Double(value)
                }
            } else {
                // Signed 16-bit
                storedValues = stride(from: 0, to: frameData.count, by: 2).map { offset in
                    let value = frameData.withUnsafeBytes { bytes in
                        bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)
                    }
                    return Double(value)
                }
            }
        } else {
            return nil
        }
        
        // Apply real world value mapping
        return applyMapping(to: storedValues, using: mapping)
    }
    
    // MARK: - Float Pixel Data Extraction
    
    /// Extract parametric values from 32-bit floating point pixel data
    ///
    /// Floating point parametric maps directly store physical quantity values,
    /// but may still have real world value mapping applied for unit conversion.
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data containing 32-bit floats
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    ///   - mapping: Optional Real World Value Mapping to apply
    /// - Returns: Array of Double values representing physical quantities
    public static func extractFloatFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int,
        mapping: RealWorldValueMapping? = nil
    ) -> [Double]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
            return nil
        }
        
        let totalPixels = rows * columns
        let bytesPerFrame = totalPixels * 4  // 4 bytes per float
        let frameOffset = frameIndex * bytesPerFrame
        
        guard frameOffset + bytesPerFrame <= pixelData.count else {
            return nil
        }
        
        let frameData = pixelData.subdata(in: frameOffset..<(frameOffset + bytesPerFrame))
        
        // Extract 32-bit float values
        let floatValues = stride(from: 0, to: frameData.count, by: 4).map { offset in
            frameData.withUnsafeBytes { bytes in
                Double(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self))
            }
        }
        
        // Apply mapping if provided
        if let mapping = mapping {
            return applyMapping(to: floatValues, using: mapping)
        }
        
        return floatValues
    }
    
    // MARK: - Double Pixel Data Extraction
    
    /// Extract parametric values from 64-bit double precision floating point pixel data
    ///
    /// Double precision parametric maps directly store high-precision physical quantity values,
    /// but may still have real world value mapping applied for unit conversion.
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data containing 64-bit doubles
    ///   - frameIndex: The frame index to extract (0-based)
    ///   - rows: Number of rows in the frame
    ///   - columns: Number of columns in the frame
    ///   - mapping: Optional Real World Value Mapping to apply
    /// - Returns: Array of Double values representing physical quantities
    public static func extractDoubleFrame(
        from pixelData: Data,
        frameIndex: Int,
        rows: Int,
        columns: Int,
        mapping: RealWorldValueMapping? = nil
    ) -> [Double]? {
        guard frameIndex >= 0, rows > 0, columns > 0 else {
            return nil
        }
        
        let totalPixels = rows * columns
        let bytesPerFrame = totalPixels * 8  // 8 bytes per double
        let frameOffset = frameIndex * bytesPerFrame
        
        guard frameOffset + bytesPerFrame <= pixelData.count else {
            return nil
        }
        
        let frameData = pixelData.subdata(in: frameOffset..<(frameOffset + bytesPerFrame))
        
        // Extract 64-bit double values
        let doubleValues = stride(from: 0, to: frameData.count, by: 8).map { offset in
            frameData.withUnsafeBytes { bytes in
                bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
            }
        }
        
        // Apply mapping if provided
        if let mapping = mapping {
            return applyMapping(to: doubleValues, using: mapping)
        }
        
        return doubleValues
    }
    
    // MARK: - Frame Extraction from ParametricMap
    
    /// Extract parametric values for a specific frame from a ParametricMap
    ///
    /// Automatically determines the pixel data type and applies appropriate extraction.
    ///
    /// - Parameters:
    ///   - parametricMap: The Parametric Map object
    ///   - pixelData: The pixel data from the DICOM file
    ///   - frameIndex: The frame index to extract (0-based)
    /// - Returns: Array of Double values representing physical quantities
    public static func extractFrame(
        from parametricMap: ParametricMap,
        pixelData: Data,
        frameIndex: Int
    ) -> [Double]? {
        // Get the appropriate mapping for this frame
        let mapping = getMapping(for: frameIndex, from: parametricMap)
        
        // Determine pixel data type based on bits allocated and pixel representation
        let bitsAllocated = parametricMap.bitsAllocated
        let pixelRepresentation = parametricMap.pixelRepresentation
        
        // Float (32-bit IEEE)
        if bitsAllocated == 32 && pixelRepresentation == 0 {
            return extractFloatFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: parametricMap.rows,
                columns: parametricMap.columns,
                mapping: mapping
            )
        }
        // Double (64-bit IEEE)
        else if bitsAllocated == 64 && pixelRepresentation == 0 {
            return extractDoubleFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: parametricMap.rows,
                columns: parametricMap.columns,
                mapping: mapping
            )
        }
        // Integer (8 or 16-bit)
        else if (bitsAllocated == 8 || bitsAllocated == 16) && mapping != nil {
            return extractIntegerFrame(
                from: pixelData,
                frameIndex: frameIndex,
                rows: parametricMap.rows,
                columns: parametricMap.columns,
                bitsAllocated: bitsAllocated,
                pixelRepresentation: pixelRepresentation,
                mapping: mapping!
            )
        }
        
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    /// Apply Real World Value Mapping to stored values
    private static func applyMapping(
        to values: [Double],
        using mapping: RealWorldValueMapping
    ) -> [Double] {
        switch mapping.mapping {
        case .linear(let slope, let intercept):
            // RealWorldValue = slope * StoredValue + intercept
            return values.map { slope * $0 + intercept }
            
        case .lut(let firstValueMapped, let lastValueMapped, let lutData):
            // Map stored values through LUT
            return values.map { storedValue in
                applyLUT(
                    storedValue: storedValue,
                    firstValueMapped: firstValueMapped,
                    lastValueMapped: lastValueMapped,
                    lutData: lutData
                )
            }
        }
    }
    
    /// Apply LUT-based mapping to a single value
    private static func applyLUT(
        storedValue: Double,
        firstValueMapped: Double,
        lastValueMapped: Double,
        lutData: [Double]
    ) -> Double {
        guard !lutData.isEmpty else {
            return storedValue
        }
        
        // Clamp stored value to LUT range
        let clampedValue = max(firstValueMapped, min(lastValueMapped, storedValue))
        
        // Map to LUT index
        let lutRange = lastValueMapped - firstValueMapped
        guard lutRange > 0 else {
            return lutData[0]
        }
        
        let normalizedValue = (clampedValue - firstValueMapped) / lutRange
        let lutIndex = normalizedValue * Double(lutData.count - 1)
        
        // Interpolate between LUT entries
        let lowerIndex = Int(floor(lutIndex))
        let upperIndex = min(lowerIndex + 1, lutData.count - 1)
        let fraction = lutIndex - Double(lowerIndex)
        
        let lowerValue = lutData[lowerIndex]
        let upperValue = lutData[upperIndex]
        
        return lowerValue + fraction * (upperValue - lowerValue)
    }
    
    /// Get the appropriate mapping for a frame
    private static func getMapping(
        for frameIndex: Int,
        from parametricMap: ParametricMap
    ) -> RealWorldValueMapping? {
        // Check per-frame mapping first
        if frameIndex < parametricMap.perFrameFunctionalGroups.count {
            _ = parametricMap.perFrameFunctionalGroups[frameIndex]
            // Try to extract mapping from frame functional group
            // For now, fall back to shared mapping
        }
        
        // Use first shared mapping as default
        return parametricMap.realWorldValueMappings.first
    }
}
