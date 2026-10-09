// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (bit reader; ITU-T bitstream syntax is out of scope)
//
// BitstreamReader.swift
// DICOMKit
//
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation

/// A big-endian bit reader over a byte buffer, with the Exp-Golomb decoding that
/// H.264 and HEVC parameter sets are written in.
///
/// Coded video parameter sets are bit-packed rather than byte-aligned, so reading
/// them means tracking a bit position rather than a byte offset. All multi-bit
/// reads take the most significant bit first, which is how both specifications
/// define `u(n)`.
///
/// Reference: ITU-T H.264 Section 7.2, ITU-T H.265 Section 7.2 (syntax descriptors)
public struct BitstreamReader {

    /// The bytes being read.
    private let data: [UInt8]

    /// The next bit to read, counted from the first bit of `data`.
    private(set) public var bitPosition: Int

    /// Creates a reader over a byte buffer.
    public init(_ data: Data) {
        self.data = [UInt8](data)
        self.bitPosition = 0
    }

    /// Creates a reader over a byte array.
    public init(bytes: [UInt8]) {
        self.data = bytes
        self.bitPosition = 0
    }

    /// The total number of readable bits.
    public var bitCount: Int { data.count * 8 }

    /// The number of bits not yet consumed.
    public var bitsRemaining: Int { max(0, bitCount - bitPosition) }

    /// Whether at least `count` bits remain.
    public func canRead(_ count: Int) -> Bool { bitsRemaining >= count }

    // MARK: - Fixed-width reads

    /// Reads a single bit as a Bool, or nil past the end of the buffer.
    ///
    /// Corresponds to the `u(1)` / `flag` syntax descriptor.
    public mutating func readBit() -> Bool? {
        guard bitPosition < bitCount else { return nil }
        let byteIndex = bitPosition >> 3
        let bitIndex = 7 - (bitPosition & 7)
        bitPosition += 1
        return (data[byteIndex] >> UInt8(bitIndex)) & 1 == 1
    }

    /// Reads `count` bits as an unsigned integer, most significant bit first.
    ///
    /// Corresponds to the `u(n)` syntax descriptor. Returns nil if fewer than
    /// `count` bits remain, or if `count` exceeds 32 (no video parameter-set field
    /// is wider, and a wider read is a caller bug rather than a stream property).
    public mutating func readBits(_ count: Int) -> UInt32? {
        guard count >= 0, count <= 32 else { return nil }
        guard count > 0 else { return 0 }
        guard canRead(count) else { return nil }

        var value: UInt32 = 0
        for _ in 0..<count {
            guard let bit = readBit() else { return nil }
            value = (value << 1) | (bit ? 1 : 0)
        }
        return value
    }

    /// Reads `count` bits as a 64-bit unsigned integer.
    ///
    /// Some HEVC fields (the 48-bit `general_..._compatibility` block, for one) are
    /// wider than 32 bits.
    public mutating func readBits64(_ count: Int) -> UInt64? {
        guard count >= 0, count <= 64 else { return nil }
        guard count > 0 else { return 0 }
        guard canRead(count) else { return nil }

        var value: UInt64 = 0
        for _ in 0..<count {
            guard let bit = readBit() else { return nil }
            value = (value << 1) | (bit ? 1 : 0)
        }
        return value
    }

    /// Advances the read position by `count` bits without decoding them.
    ///
    /// - Returns: false if fewer than `count` bits remain, leaving the position put.
    @discardableResult
    public mutating func skipBits(_ count: Int) -> Bool {
        guard count >= 0, canRead(count) else { return false }
        bitPosition += count
        return true
    }

    /// Aligns the read position to the next byte boundary.
    public mutating func alignToByte() {
        let remainder = bitPosition & 7
        if remainder != 0 {
            bitPosition += 8 - remainder
        }
    }

    // MARK: - Exp-Golomb

    /// Decodes an unsigned Exp-Golomb value — the `ue(v)` syntax descriptor.
    ///
    /// The encoding is `leadingZeros` zero bits, a one bit, then `leadingZeros`
    /// more bits; the value is `2^leadingZeros - 1 + suffix`.
    ///
    /// Returns nil on a truncated code, or when the leading-zero run exceeds 32,
    /// which no legal value produces and which would otherwise overflow.
    ///
    /// Reference: ITU-T H.264 Section 9.1
    public mutating func readUE() -> UInt32? {
        var leadingZeros = 0
        while true {
            guard let bit = readBit() else { return nil }
            if bit { break }
            leadingZeros += 1
            // A legal ue(v) value fits in 32 bits; a longer run means the caller
            // is parsing misaligned data, and continuing would overflow.
            if leadingZeros > 32 { return nil }
        }

        guard leadingZeros > 0 else { return 0 }
        guard let suffix = readBits(leadingZeros) else { return nil }

        // (1 << leadingZeros) - 1 + suffix, computed in 64 bits so a 32-bit
        // leadingZeros run cannot overflow before the range check.
        let value = (UInt64(1) << UInt64(leadingZeros)) - 1 + UInt64(suffix)
        guard value <= UInt64(UInt32.max) else { return nil }
        return UInt32(value)
    }

    /// Decodes a signed Exp-Golomb value — the `se(v)` syntax descriptor.
    ///
    /// The unsigned code word `k` maps to `(-1)^(k+1) * ceil(k / 2)`, so 1 -> 1,
    /// 2 -> -1, 3 -> 2, 4 -> -2, and so on.
    ///
    /// Reference: ITU-T H.264 Section 9.1.1
    public mutating func readSE() -> Int32? {
        guard let codeNum = readUE() else { return nil }
        guard codeNum > 0 else { return 0 }

        let magnitude = Int64((codeNum + 1) / 2)
        let value = (codeNum % 2 == 1) ? magnitude : -magnitude
        guard value >= Int64(Int32.min), value <= Int64(Int32.max) else { return nil }
        return Int32(value)
    }
}

// MARK: - NAL Unit Handling

/// Helpers for the byte-level structure that wraps H.264 and HEVC parameter sets.
public enum NALUnit {

    /// Removes emulation prevention bytes, turning a NAL unit's payload into the
    /// RBSP the syntax is defined over.
    ///
    /// An encoder inserts `0x03` after any `0x00 0x00` that would otherwise be
    /// followed by `0x00`, `0x01`, `0x02` or `0x03`, so that a start code can never
    /// appear inside a payload. Parsing without stripping these silently corrupts
    /// every field beyond the first occurrence.
    ///
    /// Reference: ITU-T H.264 Section 7.3.1, ITU-T H.265 Section 7.3.1.1
    public static func removeEmulationPrevention(_ data: Data) -> Data {
        guard data.count >= 3 else { return data }

        var output = Data(capacity: data.count)
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            // 00 00 03 -> drop the 03, but only when it is an emulation prevention
            // byte: the byte after it must be 00, 01, 02 or 03.
            if index + 2 < bytes.count,
               bytes[index] == 0x00,
               bytes[index + 1] == 0x00,
               bytes[index + 2] == 0x03 {
                let follows = index + 3 < bytes.count ? bytes[index + 3] : 0x00
                if follows <= 0x03 {
                    output.append(0x00)
                    output.append(0x00)
                    index += 3
                    continue
                }
            }
            output.append(bytes[index])
            index += 1
        }

        return output
    }

    /// Splits an Annex B byte stream into its NAL unit payloads.
    ///
    /// Start codes are `00 00 01` or `00 00 00 01`; the returned payloads exclude
    /// them and still carry their emulation prevention bytes.
    ///
    /// Reference: ITU-T H.264 Annex B
    public static func splitAnnexB(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return [] }

        var starts: [(payloadStart: Int, codeStart: Int)] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0x00, bytes[index + 1] == 0x00 {
                if bytes[index + 2] == 0x01 {
                    starts.append((index + 3, index))
                    index += 3
                    continue
                }
                if index + 3 < bytes.count, bytes[index + 2] == 0x00, bytes[index + 3] == 0x01 {
                    starts.append((index + 4, index))
                    index += 4
                    continue
                }
            }
            index += 1
        }

        guard !starts.isEmpty else { return [] }

        var units: [Data] = []
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1].codeStart : bytes.count
            guard start.payloadStart < end else { continue }
            units.append(Data(bytes[start.payloadStart..<end]))
        }
        return units
    }

    /// Splits a length-prefixed sample, the ISO-BMFF form of a coded picture,
    /// into its NAL units.
    ///
    /// MP4 stores NAL units behind a big-endian length of 1, 2 or 4 bytes - the
    /// `lengthSizeMinusOne + 1` of the `avcC` / `hvcC` record - rather than
    /// behind Annex B start codes. A truncated or malformed length ends the walk
    /// rather than misreading the rest of the sample.
    ///
    /// Reference: ISO/IEC 14496-15 Sections 5.3.2 and 8.3.2
    public static func splitLengthPrefixed(_ data: Data, lengthSize: Int) -> [Data] {
        guard [1, 2, 4].contains(lengthSize) else { return [] }
        let bytes = [UInt8](data)
        var units: [Data] = []
        var offset = 0
        while offset + lengthSize <= bytes.count {
            var length = 0
            for index in 0..<lengthSize {
                length = (length << 8) | Int(bytes[offset + index])
            }
            offset += lengthSize
            guard length > 0, offset + length <= bytes.count else { break }
            units.append(Data(bytes[offset..<(offset + length)]))
            offset += length
        }
        return units
    }

    /// Whether the buffer begins with an Annex B start code.
    public static func hasAnnexBStartCode(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 3, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01 {
            return true
        }
        if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x00, bytes[3] == 0x01 {
            return true
        }
        return false
    }
}
