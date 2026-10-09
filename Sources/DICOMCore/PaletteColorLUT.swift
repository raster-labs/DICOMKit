import Foundation

/// DICOM Palette Color Lookup Table
///
/// Contains the Red, Green, and Blue lookup tables used for PALETTE COLOR
/// photometric interpretation images. Each pixel value in the image data
/// is used as an index into these lookup tables to determine the final
/// RGB color.
///
/// Reference: DICOM PS3.3 C.7.6.3.1.5 - Palette Color Lookup Table Descriptor
/// Reference: DICOM PS3.3 C.7.6.3.1.6 - Palette Color Lookup Table Data
/// Reference: DICOM PS3.3 C.7.9 - Palette Color Lookup Table Module
///
/// NEMA-verified: 2026a, checked 2026-09-25 — descriptor semantics (first value 0 means 2^16 entries; out-of-range input clamps to the first or last entry; 8 or 16 bits per entry) match PS3.3 2026a C.7.6.3.1.5, and the 8-bit normalisation follows C.7.6.3.1.6. The first citation named the wrong section title; corrected.
public struct PaletteColorLUT: Sendable, Equatable {
    /// Descriptor containing the LUT metadata
    ///
    /// Contains:
    /// - Number of entries in the LUT
    /// - First mapped pixel value
    /// - Number of bits for each entry (8 or 16)
    public struct Descriptor: Sendable, Equatable {
        /// Number of entries in the lookup table
        ///
        /// Per DICOM, a value of 0 means 65536 entries (2^16).
        public let numberOfEntries: Int
        
        /// First input value mapped by the LUT
        ///
        /// Pixel values below this value map to the first LUT entry.
        public let firstMappedValue: Int
        
        /// Number of bits for each entry (8 or 16)
        public let bitsPerEntry: Int
        
        /// Creates a LUT descriptor from the raw descriptor values
        /// - Parameters:
        ///   - numberOfEntries: Number of entries (0 = 65536)
        ///   - firstMappedValue: First mapped pixel value
        ///   - bitsPerEntry: Bits per entry (8 or 16)
        public init(numberOfEntries: Int, firstMappedValue: Int, bitsPerEntry: Int) {
            // Per DICOM PS3.3 C.7.6.3.1.5, a value of 0 means 2^16 entries
            self.numberOfEntries = numberOfEntries == 0 ? 65536 : numberOfEntries
            self.firstMappedValue = firstMappedValue
            self.bitsPerEntry = bitsPerEntry
        }
        
        /// Creates a LUT descriptor from raw DICOM descriptor data
        ///
        /// The DICOM Palette Color Lookup Table Descriptor contains 3 values:
        /// - Number of entries in the LUT
        /// - First mapped pixel value
        /// - Number of bits for each entry
        ///
        /// - Parameter data: Raw descriptor data (6 bytes for US/SS VM=3)
        /// - Returns: Descriptor if valid, nil otherwise
        public static func parse(from data: Data) -> Descriptor? {
            guard data.count >= 6 else {
                return nil
            }
            
            let numberOfEntries = Int(data.readUInt16LE(at: 0) ?? 0)
            let firstMappedValue = Int(data.readUInt16LE(at: 2) ?? 0)
            let bitsPerEntry = Int(data.readUInt16LE(at: 4) ?? 0)
            
            // Bits per entry must be 8 or 16
            guard bitsPerEntry == 8 || bitsPerEntry == 16 else {
                return nil
            }
            
            return Descriptor(
                numberOfEntries: numberOfEntries,
                firstMappedValue: firstMappedValue,
                bitsPerEntry: bitsPerEntry
            )
        }
    }
    
    /// Red LUT descriptor
    public let redDescriptor: Descriptor
    
    /// Green LUT descriptor
    public let greenDescriptor: Descriptor
    
    /// Blue LUT descriptor
    public let blueDescriptor: Descriptor
    
    /// Red LUT data (normalized to 16-bit values)
    public let redLUT: [UInt16]
    
    /// Green LUT data (normalized to 16-bit values)
    public let greenLUT: [UInt16]
    
    /// Blue LUT data (normalized to 16-bit values)
    public let blueLUT: [UInt16]
    
    /// Creates a Palette Color LUT from descriptors and data
    /// - Parameters:
    ///   - redDescriptor: Red LUT descriptor
    ///   - greenDescriptor: Green LUT descriptor
    ///   - blueDescriptor: Blue LUT descriptor
    ///   - redLUT: Red LUT data
    ///   - greenLUT: Green LUT data
    ///   - blueLUT: Blue LUT data
    public init(
        redDescriptor: Descriptor,
        greenDescriptor: Descriptor,
        blueDescriptor: Descriptor,
        redLUT: [UInt16],
        greenLUT: [UInt16],
        blueLUT: [UInt16]
    ) {
        self.redDescriptor = redDescriptor
        self.greenDescriptor = greenDescriptor
        self.blueDescriptor = blueDescriptor
        self.redLUT = redLUT
        self.greenLUT = greenLUT
        self.blueLUT = blueLUT
    }
    
    /// Looks up the RGB color for a given pixel value
    ///
    /// - Parameter pixelValue: The pixel value to look up
    /// - Returns: Tuple of (red, green, blue) values normalized to 0-255 range
    public func lookup(_ pixelValue: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        // Calculate index into LUT
        let redIndex = clampIndex(pixelValue, for: redDescriptor)
        let greenIndex = clampIndex(pixelValue, for: greenDescriptor)
        let blueIndex = clampIndex(pixelValue, for: blueDescriptor)
        
        // Get 16-bit values from LUT
        let red16 = redLUT[redIndex]
        let green16 = greenLUT[greenIndex]
        let blue16 = blueLUT[blueIndex]
        
        // Normalize to 8-bit
        let red8 = normalize(red16)
        let green8 = normalize(green16)
        let blue8 = normalize(blue16)
        
        return (red8, green8, blue8)
    }
    
    /// Calculates and clamps the LUT index for a pixel value
    private func clampIndex(_ pixelValue: Int, for descriptor: Descriptor) -> Int {
        let index = pixelValue - descriptor.firstMappedValue
        return max(0, min(descriptor.numberOfEntries - 1, index))
    }
    
    /// Normalizes a 16-bit LUT value to 8-bit
    ///
    /// Per PS3.3 C.7.6.3.1.6, palette values are scaled across the full range of
    /// the entry width, so the high byte of a 16-bit entry is its 8-bit intensity.
    /// `parseLUTData` places 8-bit entries in the high byte, so one rule serves both.
    private func normalize(_ value: UInt16) -> UInt8 {
        // High byte contains the significant data for both 8-bit and 16-bit LUTs
        return UInt8(value >> 8)
    }
    
    /// Parses LUT data from raw DICOM data
    ///
    /// - Parameters:
    ///   - data: Raw LUT data
    ///   - descriptor: LUT descriptor for this data
    /// - Returns: Array of 16-bit LUT values, or nil if parsing fails
    public static func parseLUTData(from data: Data, descriptor: Descriptor) -> [UInt16]? {
        var result: [UInt16] = []
        result.reserveCapacity(descriptor.numberOfEntries)
        
        if descriptor.bitsPerEntry == 8 {
            // 8-bit entries are stored "in a format equivalent to 8 bits allocated"
            // (PS3.3 C.7.6.3.1.5), i.e. one byte each; widen to the high byte so the
            // lookup can treat every entry as 16-bit. The second branch below is
            // unreachable for well-formed data and is kept only as a fallback.
            if data.count >= descriptor.numberOfEntries {
                // Individual byte storage. Index from startIndex so a sliced
                // Data (non-zero startIndex) is read correctly rather than trapping.
                for i in 0..<descriptor.numberOfEntries {
                    let value = UInt16(data[data.startIndex + i]) << 8
                    result.append(value)
                }
            } else if data.count >= descriptor.numberOfEntries * 2 {
                // 16-bit word storage with value in high byte
                for i in 0..<descriptor.numberOfEntries {
                    let offset = i * 2
                    if let value = data.readUInt16LE(at: offset) {
                        result.append(value)
                    }
                }
            } else {
                return nil
            }
        } else {
            // 16-bit LUT entries
            guard data.count >= descriptor.numberOfEntries * 2 else {
                return nil
            }
            
            for i in 0..<descriptor.numberOfEntries {
                let offset = i * 2
                if let value = data.readUInt16LE(at: offset) {
                    result.append(value)
                }
            }
        }
        
        return result
    }
}
