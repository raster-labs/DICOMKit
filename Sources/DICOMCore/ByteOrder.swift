import Foundation

/// Utilities for reading byte data with different endianness
///
/// All non-retired DICOM Transfer Syntaxes use Little Endian byte ordering. The Big
/// Endian readers exist for the retired Explicit VR Big Endian Transfer Syntax
/// (1.2.840.10008.1.2.2), whose description was removed from PS3.5 in 2016b.
///
/// Reference: PS3.5 Section 7.3 - Little Endian Byte Ordering (which also records the
/// retirement of Big Endian byte ordering and points to PS3.5 2016b for its definition).
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the byte-order rules match PS3.5 2026a §7.3
/// (least significant byte first; multi-byte swapping applies to binary VRs only), and
/// 1.2.840.10008.1.2.2 is "Explicit VR Big Endian (Retired)" in PS3.6 2026a Table A-1.
/// The section numbers cited before (§7.1.1, §7.1.2) were wrong: in 2026a those are
/// "Data Element Fields" and "Data Element Structure with Explicit VR".
extension Data {
    /// Reads a 16-bit unsigned integer in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt16 value, or nil if offset is out of bounds
    public func readUInt16LE(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else {
            return nil
        }
        
        let byte0 = UInt16(self[startIndex + offset])
        let byte1 = UInt16(self[startIndex + offset + 1])
        
        return byte0 | (byte1 << 8)
    }
    
    /// Reads a 32-bit unsigned integer in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt32 value, or nil if offset is out of bounds
    public func readUInt32LE(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else {
            return nil
        }
        
        let byte0 = UInt32(self[startIndex + offset])
        let byte1 = UInt32(self[startIndex + offset + 1])
        let byte2 = UInt32(self[startIndex + offset + 2])
        let byte3 = UInt32(self[startIndex + offset + 3])
        
        return byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
    }
    
    /// Reads a 16-bit signed integer in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Int16 value, or nil if offset is out of bounds
    public func readInt16LE(at offset: Int) -> Int16? {
        guard let value = readUInt16LE(at: offset) else {
            return nil
        }
        return Int16(bitPattern: value)
    }
    
    /// Reads a 32-bit signed integer in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Int32 value, or nil if offset is out of bounds
    public func readInt32LE(at offset: Int) -> Int32? {
        guard let value = readUInt32LE(at: offset) else {
            return nil
        }
        return Int32(bitPattern: value)
    }
    
    /// Reads a 32-bit floating point number in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Float32 value, or nil if offset is out of bounds
    public func readFloat32LE(at offset: Int) -> Float32? {
        guard let bits = readUInt32LE(at: offset) else {
            return nil
        }
        return Float32(bitPattern: bits)
    }
    
    /// Reads a 64-bit floating point number in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Float64 value, or nil if offset is out of bounds
    public func readFloat64LE(at offset: Int) -> Float64? {
        guard offset + 8 <= count else {
            return nil
        }
        
        let byte0 = UInt64(self[startIndex + offset])
        let byte1 = UInt64(self[startIndex + offset + 1])
        let byte2 = UInt64(self[startIndex + offset + 2])
        let byte3 = UInt64(self[startIndex + offset + 3])
        let byte4 = UInt64(self[startIndex + offset + 4])
        let byte5 = UInt64(self[startIndex + offset + 5])
        let byte6 = UInt64(self[startIndex + offset + 6])
        let byte7 = UInt64(self[startIndex + offset + 7])
        
        let bits = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24) |
                   (byte4 << 32) | (byte5 << 40) | (byte6 << 48) | (byte7 << 56)
        
        return Float64(bitPattern: bits)
    }
    
    // MARK: - Big Endian Byte Reading
    
    /// Reads a 16-bit unsigned integer in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt16 value, or nil if offset is out of bounds
    public func readUInt16BE(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else {
            return nil
        }
        
        let byte0 = UInt16(self[startIndex + offset])
        let byte1 = UInt16(self[startIndex + offset + 1])
        
        return (byte0 << 8) | byte1
    }
    
    /// Reads a 32-bit unsigned integer in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt32 value, or nil if offset is out of bounds
    public func readUInt32BE(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else {
            return nil
        }
        
        let byte0 = UInt32(self[startIndex + offset])
        let byte1 = UInt32(self[startIndex + offset + 1])
        let byte2 = UInt32(self[startIndex + offset + 2])
        let byte3 = UInt32(self[startIndex + offset + 3])
        
        return (byte0 << 24) | (byte1 << 16) | (byte2 << 8) | byte3
    }
    
    /// Reads a 16-bit signed integer in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Int16 value, or nil if offset is out of bounds
    public func readInt16BE(at offset: Int) -> Int16? {
        guard let value = readUInt16BE(at: offset) else {
            return nil
        }
        return Int16(bitPattern: value)
    }
    
    /// Reads a 32-bit signed integer in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Int32 value, or nil if offset is out of bounds
    public func readInt32BE(at offset: Int) -> Int32? {
        guard let value = readUInt32BE(at: offset) else {
            return nil
        }
        return Int32(bitPattern: value)
    }
    
    /// Reads a 32-bit floating point number in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Float32 value, or nil if offset is out of bounds
    public func readFloat32BE(at offset: Int) -> Float32? {
        guard let bits = readUInt32BE(at: offset) else {
            return nil
        }
        return Float32(bitPattern: bits)
    }
    
    /// Reads a 64-bit floating point number in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: Float64 value, or nil if offset is out of bounds
    public func readFloat64BE(at offset: Int) -> Float64? {
        guard offset + 8 <= count else {
            return nil
        }
        
        let byte0 = UInt64(self[startIndex + offset])
        let byte1 = UInt64(self[startIndex + offset + 1])
        let byte2 = UInt64(self[startIndex + offset + 2])
        let byte3 = UInt64(self[startIndex + offset + 3])
        let byte4 = UInt64(self[startIndex + offset + 4])
        let byte5 = UInt64(self[startIndex + offset + 5])
        let byte6 = UInt64(self[startIndex + offset + 6])
        let byte7 = UInt64(self[startIndex + offset + 7])
        
        let bits = (byte0 << 56) | (byte1 << 48) | (byte2 << 40) | (byte3 << 32) |
                   (byte4 << 24) | (byte5 << 16) | (byte6 << 8) | byte7
        
        return Float64(bitPattern: bits)
    }
    
    // MARK: - 64-bit Integer Reading
    
    /// Reads a 64-bit unsigned integer in Little Endian byte order
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt64 value, or nil if offset is out of bounds
    public func readUInt64LE(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else {
            return nil
        }
        
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(self[startIndex + offset + i]) << (i * 8)
        }
        return result
    }
    
    /// Reads a 64-bit unsigned integer in Big Endian byte order
    ///
    /// Used by the retired Explicit VR Big Endian Transfer Syntax (1.2.840.10008.1.2.2).
    /// Reference: PS3.5 Section 7.3 (Big Endian byte ordering retired; see PS3.5 2016b)
    /// - Parameter offset: Byte offset to read from
    /// - Returns: UInt64 value, or nil if offset is out of bounds
    public func readUInt64BE(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else {
            return nil
        }
        
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(self[startIndex + offset + i]) << ((7 - i) * 8)
        }
        return result
    }
}
