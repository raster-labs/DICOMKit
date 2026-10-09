import Foundation

#if canImport(ImageIO)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Native JPEG 2000 codec using Apple's ImageIO framework
///
/// Supports JPEG 2000 lossless and lossy transfer syntaxes.
/// Provides both decoding and encoding capabilities.
/// Reference: DICOM PS3.5 Section A.4.4
///
/// - Note: Deprecated in favour of ``J2KSwiftCodec`` and ``HTJ2KCodec``,
///   which use J2KSwift for cross-platform, higher-fidelity JPEG 2000 support.
@available(*, deprecated, renamed: "J2KSwiftCodec", message: "Use J2KSwiftCodec or HTJ2KCodec instead. NativeJPEG2000Codec relies on Apple ImageIO which has known 12-bit grayscale limitations.")
/// NEMA-verified: 2026a, checked 2026-09-25 — the two UIDs come from `TransferSyntax` (PS3.6 2026a Table A-1) and the J2C-codestream requirement is PS3.5 2026a A.4.4. `canEncode` (8 or 16 allocated) is a subset of Table 8.2.4-1, which allows up to 40 bits; an ImageIO limit, not a standard claim.
public struct NativeJPEG2000Codec: ImageCodec, ImageEncoder, Sendable {
    /// Supported JPEG 2000 transfer syntaxes for decoding
    public static let supportedTransferSyntaxes: [String] = [
        TransferSyntax.jpeg2000Lossless.uid,  // 1.2.840.10008.1.2.4.90
        TransferSyntax.jpeg2000.uid           // 1.2.840.10008.1.2.4.91
    ]
    
    /// Supported JPEG 2000 transfer syntaxes for encoding
    ///
    /// ImageIO supports both lossless and lossy JPEG 2000 encoding.
    public static let supportedEncodingTransferSyntaxes: [String] = [
        TransferSyntax.jpeg2000Lossless.uid,  // 1.2.840.10008.1.2.4.90
        TransferSyntax.jpeg2000.uid           // 1.2.840.10008.1.2.4.91
    ]
    
    public init() {}
    
    // MARK: - Decoding
    
    /// Decodes a JPEG 2000-compressed frame
    /// - Parameters:
    ///   - frameData: JPEG 2000 compressed data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Frame index (unused for single frame decode)
    /// - Returns: Uncompressed pixel data
    /// - Throws: DICOMError if decoding fails
    public func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
        guard !frameData.isEmpty else {
            throw DICOMError.parsingFailed("Empty JPEG 2000 data")
        }
        
        // Create image source from JPEG 2000 data
        // ImageIO can handle JP2 format directly
        guard let imageSource = CGImageSourceCreateWithData(frameData as CFData, nil) else {
            throw DICOMError.parsingFailed("Failed to create image source from JPEG 2000 data")
        }
        
        // Check the image type
        let typeIdentifier = CGImageSourceGetType(imageSource) as String?
        
        // Get the image
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw DICOMError.parsingFailed("Failed to decode JPEG 2000 image (type: \(typeIdentifier ?? "unknown"))")
        }
        
        // Extract pixel data from CGImage
        return try extractPixelData(from: cgImage, descriptor: descriptor)
    }
    
    // MARK: - Encoding
    
    /// Whether this encoder supports the given configuration
    public func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
        // JPEG 2000 supports 8-bit and 16-bit sample precision.
        guard descriptor.bitsAllocated == 8 || descriptor.bitsAllocated == 16 else {
            return false
        }
        
        // Support grayscale and RGB
        guard descriptor.samplesPerPixel == 1 || descriptor.samplesPerPixel == 3 else {
            return false
        }
        
        return true
    }
    
    /// Encodes a single frame to JPEG 2000 format
    /// - Parameters:
    ///   - frameData: Uncompressed frame data
    ///   - descriptor: Pixel data descriptor
    ///   - frameIndex: Zero-based frame index
    ///   - configuration: Compression configuration
    /// - Returns: JPEG 2000 compressed frame data
    /// - Throws: DICOMError if encoding fails
    public func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
        // Create CGImage from raw pixel data
        let cgImage = try createCGImage(from: frameData, descriptor: descriptor)
        
        // Encode to JPEG 2000
        return try encodeToJPEG2000(cgImage, configuration: configuration, descriptor: descriptor)
    }
    
    // MARK: - Private Decoding Helpers
    
    /// Extracts raw pixel data from a CGImage
    private func extractPixelData(from image: CGImage, descriptor: PixelDataDescriptor) throws -> Data {
        let width = image.width
        let height = image.height
        let samplesPerPixel = descriptor.samplesPerPixel
        
        // Validate dimensions
        guard width == descriptor.columns && height == descriptor.rows else {
            throw DICOMError.parsingFailed("Decoded image dimensions (\(width)x\(height)) don't match expected (\(descriptor.columns)x\(descriptor.rows))")
        }
        
        // Determine output format
        if samplesPerPixel == 1 {
            // Grayscale
            return try extractGrayscaleData(from: image, descriptor: descriptor)
        } else if samplesPerPixel == 3 {
            // RGB
            return try extractRGBData(from: image, descriptor: descriptor)
        } else {
            throw DICOMError.parsingFailed("Unsupported samples per pixel: \(samplesPerPixel)")
        }
    }
    
    /// Extracts grayscale pixel data
    private func extractGrayscaleData(from image: CGImage, descriptor: PixelDataDescriptor) throws -> Data {
        let width = descriptor.columns
        let height = descriptor.rows
        let bytesPerSample = descriptor.bytesPerSample
        
        // Create grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo: CGBitmapInfo
        
        if bytesPerSample == 1 {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        } else {
            // 16-bit grayscale
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        }
        
        let bytesPerRow = width * bytesPerSample
        let totalBytes = bytesPerRow * height
        
        var pixelData = Data(count: totalBytes)
        
        try pixelData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else {
                throw DICOMError.parsingFailed("Failed to get pixel buffer address")
            }
            
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: bytesPerSample * 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                throw DICOMError.parsingFailed("Failed to create grayscale context")
            }
            
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return normalizeDecoded16BitSamplesIfNeeded(pixelData, descriptor: descriptor)
    }
    
    /// Extracts RGB pixel data
    private func extractRGBData(from image: CGImage, descriptor: PixelDataDescriptor) throws -> Data {
        let width = descriptor.columns
        let height = descriptor.rows
        let bytesPerSample = descriptor.bytesPerSample
        
        // For RGB, we need 3 samples per pixel
        let bytesPerPixel = 3 * bytesPerSample
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height
        
        // Create RGB context (using RGBA internally, then strip alpha)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rgbaBytesPerRow = width * 4 * bytesPerSample
        var rgbaData = Data(count: rgbaBytesPerRow * height)
        
        let bitmapInfo: CGBitmapInfo
        if bytesPerSample == 1 {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        } else {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        }
        
        try rgbaData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else {
                throw DICOMError.parsingFailed("Failed to get pixel buffer address")
            }
            
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: bytesPerSample * 8,
                bytesPerRow: rgbaBytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else {
                throw DICOMError.parsingFailed("Failed to create RGB context")
            }
            
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        // Strip alpha channel to get pure RGB
        var rgbData = Data(capacity: totalBytes)
        
        if bytesPerSample == 1 {
            for y in 0..<height {
                for x in 0..<width {
                    let rgbaOffset = y * rgbaBytesPerRow + x * 4
                    rgbData.append(rgbaData[rgbaOffset])     // R
                    rgbData.append(rgbaData[rgbaOffset + 1]) // G
                    rgbData.append(rgbaData[rgbaOffset + 2]) // B
                }
            }
        } else {
            for y in 0..<height {
                for x in 0..<width {
                    let rgbaOffset = y * rgbaBytesPerRow + x * 8
                    rgbData.append(rgbaData[rgbaOffset])     // R low
                    rgbData.append(rgbaData[rgbaOffset + 1]) // R high
                    rgbData.append(rgbaData[rgbaOffset + 2]) // G low
                    rgbData.append(rgbaData[rgbaOffset + 3]) // G high
                    rgbData.append(rgbaData[rgbaOffset + 4]) // B low
                    rgbData.append(rgbaData[rgbaOffset + 5]) // B high
                }
            }
        }
        
        return normalizeDecoded16BitSamplesIfNeeded(rgbData, descriptor: descriptor)
    }

    /// Normalizes ImageIO-decoded 16-bit samples back into the DICOM stored-bit range.
    ///
    /// ImageIO may expand sub-16-bit JPEG 2000 precision into full-range 16-bit samples.
    /// DICOM consumers expect the decoded samples to remain in the original Bits Stored range.
    private func normalizeDecoded16BitSamplesIfNeeded(_ data: Data, descriptor: PixelDataDescriptor) -> Data {
        guard descriptor.bitsAllocated == 16,
              descriptor.bitsStored > 0,
              descriptor.bitsStored < 16,
              !descriptor.isSigned,
              data.count >= 2
        else {
            return data
        }

        let maxStoredValue = UInt32(descriptor.maxPossibleValue)
        let lowBitCount = 16 - descriptor.bitsStored
        let lowBitMask = lowBitCount > 0 ? UInt16((1 << lowBitCount) - 1) : 0

        var maxDecodedValue: UInt16 = 0
        var sampleCount = 0
        var leftAlignedSampleCount = 0

        for offset in stride(from: 0, to: data.count - 1, by: 2) {
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if value > maxDecodedValue {
                maxDecodedValue = value
            }
            if lowBitMask == 0 || (value & lowBitMask) == 0 {
                leftAlignedSampleCount += 1
            }
            sampleCount += 1
        }

        guard UInt32(maxDecodedValue) > maxStoredValue else {
            return data
        }

        let looksLeftAligned = sampleCount > 0 && leftAlignedSampleCount * 100 >= sampleCount * 95
        let denominator = UInt32(UInt16.max)

        var normalized = Data(capacity: data.count)
        for offset in stride(from: 0, to: data.count - 1, by: 2) {
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let adjusted: UInt16

            if looksLeftAligned {
                adjusted = value >> lowBitCount
            } else {
                let scaled = (UInt32(value) * maxStoredValue + (denominator / 2)) / denominator
                adjusted = UInt16(min(scaled, maxStoredValue))
            }

            normalized.append(UInt8(adjusted & 0x00FF))
            normalized.append(UInt8(adjusted >> 8))
        }

        return normalized
    }
    
    // MARK: - Private Encoding Helpers
    
    /// Creates a CGImage from raw pixel data
    private func createCGImage(from data: Data, descriptor: PixelDataDescriptor) throws -> CGImage {
        let width = descriptor.columns
        let height = descriptor.rows
        let bytesPerSample = descriptor.bytesPerSample
        let samplesPerPixel = descriptor.samplesPerPixel
        
        let colorSpace: CGColorSpace
        let bitmapInfo: CGBitmapInfo
        let bytesPerRow: Int
        var processedData = data
        
        if samplesPerPixel == 1 {
            // Grayscale
            colorSpace = CGColorSpaceCreateDeviceGray()
            
            if bytesPerSample == 2 {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
                bytesPerRow = width * 2
            } else {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                bytesPerRow = width * bytesPerSample
            }
        } else if samplesPerPixel == 3 {
            // RGB - need to convert to RGBA for CGImage
            colorSpace = CGColorSpaceCreateDeviceRGB()
            if bytesPerSample == 1 {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
            } else {
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
            }
            bytesPerRow = width * 4 * bytesPerSample
            
            // Convert RGB to RGBA by adding alpha channel
            processedData = try addAlphaChannel(to: data, descriptor: descriptor)
        } else {
            throw DICOMError.parsingFailed("Unsupported samples per pixel for encoding: \(samplesPerPixel)")
        }
        
        // Create CGImage from data
        guard let dataProvider = CGDataProvider(data: processedData as CFData) else {
            throw DICOMError.parsingFailed("Failed to create data provider for encoding")
        }
        
        let bitsPerComponent = bytesPerSample * 8
        let bitsPerPixel: Int
        if samplesPerPixel == 1 {
            bitsPerPixel = bitsPerComponent
        } else {
            bitsPerPixel = 4 * bitsPerComponent // RGBA
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw DICOMError.parsingFailed("Failed to create CGImage for encoding")
        }
        
        return cgImage
    }
    
    /// Adds alpha channel to RGB data to create RGBA data
    private func addAlphaChannel(to rgbData: Data, descriptor: PixelDataDescriptor) throws -> Data {
        let width = descriptor.columns
        let height = descriptor.rows
        let bytesPerSample = descriptor.bytesPerSample
        let rgbBytesPerPixel = 3 * bytesPerSample
        let rgbaBytesPerPixel = 4 * bytesPerSample
        
        var rgbaData = Data(capacity: width * height * rgbaBytesPerPixel)
        
        if bytesPerSample == 1 {
            for y in 0..<height {
                for x in 0..<width {
                    let rgbOffset = (y * width + x) * rgbBytesPerPixel
                    guard rgbOffset + 2 < rgbData.count else {
                        throw DICOMError.parsingFailed("RGB data too short for pixel at (\(x), \(y))")
                    }
                    rgbaData.append(rgbData[rgbOffset])     // R
                    rgbaData.append(rgbData[rgbOffset + 1]) // G
                    rgbaData.append(rgbData[rgbOffset + 2]) // B
                    rgbaData.append(0xFF)                    // A (fully opaque)
                }
            }
        } else {
            // 16-bit samples
            for y in 0..<height {
                for x in 0..<width {
                    let rgbOffset = (y * width + x) * rgbBytesPerPixel
                    guard rgbOffset + 5 < rgbData.count else {
                        throw DICOMError.parsingFailed("RGB data too short for pixel at (\(x), \(y))")
                    }
                    rgbaData.append(rgbData[rgbOffset])     // R low
                    rgbaData.append(rgbData[rgbOffset + 1]) // R high
                    rgbaData.append(rgbData[rgbOffset + 2]) // G low
                    rgbaData.append(rgbData[rgbOffset + 3]) // G high
                    rgbaData.append(rgbData[rgbOffset + 4]) // B low
                    rgbaData.append(rgbData[rgbOffset + 5]) // B high
                    rgbaData.append(0xFF)                    // A low
                    rgbaData.append(0xFF)                    // A high
                }
            }
        }
        
        return rgbaData
    }
    
    /// Encodes a CGImage to JPEG 2000 data
    ///
    /// Apple's ImageIO produces JP2 file format data (with box structure), but DICOM
    /// requires the raw JPEG 2000 codestream (J2C) per PS3.5 Section A.4.4.
    /// This method encodes via ImageIO and then extracts the raw J2C codestream.
    private func encodeToJPEG2000(_ image: CGImage, configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) throws -> Data {
        let mutableData = NSMutableData()
        
        // The standard Apple UTI for JPEG 2000 is "public.jpeg-2000" (kUTTypeJPEG2000).
        // Try it first, then fall back to the JP2 identifier used by some macOS versions.
        let jp2Identifiers: [CFString] = [
            "public.jpeg-2000" as CFString,
            "org.jpeg.jp2" as CFString,
            "public.jp2" as CFString,
        ]
        
        // Debug: log available types and image info
        let availableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        let hasJP2 = availableTypes.contains("public.jpeg-2000")
        
        var destination: CGImageDestination?
        for identifier in jp2Identifiers {
            destination = CGImageDestinationCreateWithData(mutableData, identifier, 1, nil)
            if destination != nil { break }
        }
        
        guard let destination else {
            throw DICOMError.parsingFailed(
                "Failed to create JPEG 2000 image destination — "
                + "JPEG 2000 encoding may not be supported on this platform "
                + "(available=\(hasJP2), types=\(availableTypes.count), "
                + "image=\(image.width)x\(image.height) bpc=\(image.bitsPerComponent) "
                + "bpp=\(image.bitsPerPixel) cs=\(image.colorSpace?.name ?? "nil" as CFString))"
            )
        }
        
        // Set compression options
        var options: [CFString: Any] = [:]
        
        // For JPEG 2000, use lossless if preferLossless is set
        if configuration.preferLossless || configuration.quality.isLossless {
            // Lossless JPEG 2000 - quality of 1.0 means lossless
            options[kCGImageDestinationLossyCompressionQuality] = 1.0
        } else {
            // Lossy compression with specified quality
            options[kCGImageDestinationLossyCompressionQuality] = configuration.quality.value
        }
        
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw DICOMError.parsingFailed("Failed to finalize JPEG 2000 encoding")
        }
        
        let jp2Data = mutableData as Data
        
        // Extract raw J2C codestream from JP2 file format.
        // DICOM requires the raw codestream (starting with SOC marker FF 4F),
        // not the JP2 wrapper with Signature/FileType/Header boxes.
        guard let j2cData = Self.extractJ2CCodestream(from: jp2Data) else {
            // If extraction fails, check if the data is already a raw codestream
            if jp2Data.count >= 2 && jp2Data[0] == 0xFF && jp2Data[1] == 0x4F {
                return jp2Data
            }
            throw DICOMError.parsingFailed("Failed to extract JPEG 2000 codestream from encoded data")
        }
        
        return j2cData
    }
    
    /// Extracts the raw JPEG 2000 codestream (J2C) from JP2 file format data.
    ///
    /// Apple's ImageIO produces JP2 file format data containing box structures
    /// (Signature, FileType, Header, Contiguous Codestream). DICOM requires
    /// only the raw J2C codestream per PS3.5 Section A.4.4.
    ///
    /// This function parses the JP2 box structure to find the "jp2c"
    /// (Contiguous Codestream) box and returns its contents.
    ///
    /// Reference: ISO/IEC 15444-1 Annex I — JP2 file format
    private static func extractJ2CCodestream(from jp2Data: Data) -> Data? {
        let jp2cBoxType = Data("jp2c".utf8) // 0x6A, 0x70, 0x32, 0x63
        var offset = 0
        
        while offset + 8 <= jp2Data.count {
            // Read box length (big-endian UInt32)
            let b0 = UInt32(jp2Data[offset])
            let b1 = UInt32(jp2Data[offset + 1])
            let b2 = UInt32(jp2Data[offset + 2])
            let b3 = UInt32(jp2Data[offset + 3])
            let boxLength = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            
            // Read box type (4 bytes)
            let boxType = jp2Data.subdata(in: (offset + 4)..<(offset + 8))
            
            if boxType == jp2cBoxType {
                // Found the Contiguous Codestream box
                if boxLength == 0 {
                    // Box extends to end of data
                    return jp2Data.subdata(in: (offset + 8)..<jp2Data.count)
                } else if boxLength == 1 {
                    // Extended length (8-byte big-endian length at offset + 8)
                    guard offset + 16 <= jp2Data.count else { return nil }
                    return jp2Data.subdata(in: (offset + 16)..<jp2Data.count)
                } else {
                    let codestreamStart = offset + 8
                    let codestreamEnd = min(offset + Int(boxLength), jp2Data.count)
                    guard codestreamStart < codestreamEnd else { return nil }
                    return jp2Data.subdata(in: codestreamStart..<codestreamEnd)
                }
            }
            
            // Move to next box
            if boxLength == 0 {
                break // Box extends to end of data — no more boxes
            } else if boxLength == 1 {
                // Extended length
                guard offset + 16 <= jp2Data.count else { break }
                let ext = jp2Data.subdata(in: (offset + 8)..<(offset + 16))
                var extLen: UInt64 = 0
                for byte in ext { extLen = (extLen << 8) | UInt64(byte) }
                offset += Int(extLen)
            } else if boxLength < 8 {
                break // Invalid box
            } else {
                offset += Int(boxLength)
            }
        }
        
        return nil
    }
}

#endif
