// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (parser storage cursor).
import Foundation
import DICOMCore

/// Storage strategy only: all DICOM grammar remains in DICOMParser.
final class DICOMParserInput {
    private let owned: Data?
    private let source: (any DICOMVerifiedByteSource)?
    private var window: DICOMByteBuffer?
    private var windowStart = -1
    private static let windowBytes = 64 * 1024
    let count: Int
    init(data: Data) { owned = data; source = nil; count = data.count }
    init(source: any DICOMVerifiedByteSource) { owned = nil; self.source = source; count = source.count }

    func byte(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < count else { throw DICOMError.unexpectedEndOfData }
        if let owned { return owned[owned.startIndex + offset] }
        guard let source else { throw DICOMError.unexpectedEndOfData }
        let start = offset / Self.windowBytes * Self.windowBytes
        if windowStart != start {
            // Drop an obsolete immutable window before refill. No borrow escapes.
            window = nil
            window = try source.read(start..<(start + min(Self.windowBytes, count - start)), resource: .encoded)
            windowStart = start
        }
        guard let window else { throw DICOMError.unexpectedEndOfData }
        return window.withUnsafeBytes { $0[offset - start] }
    }
    func readUInt16LE(at offset: Int) throws -> UInt16? { try integer16(at: offset, little: true) }
    func readUInt16BE(at offset: Int) throws -> UInt16? { try integer16(at: offset, little: false) }
    func readUInt32LE(at offset: Int) throws -> UInt32? { try integer32(at: offset, little: true) }
    func readUInt32BE(at offset: Int) throws -> UInt32? { try integer32(at: offset, little: false) }
    private func integer16(at offset: Int, little: Bool) throws -> UInt16? {
        guard offset >= 0, offset <= count, 2 <= count - offset else { return nil }
        if let owned { return little ? owned.readUInt16LE(at: offset) : owned.readUInt16BE(at: offset) }
        let a = UInt16(try byte(at: offset)), b = UInt16(try byte(at: offset + 1))
        return little ? a | b << 8 : a << 8 | b
    }
    private func integer32(at offset: Int, little: Bool) throws -> UInt32? {
        guard offset >= 0, offset <= count, 4 <= count - offset else { return nil }
        if let owned { return little ? owned.readUInt32LE(at: offset) : owned.readUInt32BE(at: offset) }
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(try byte(at: offset + index)) << (little ? index * 8 : (3 - index) * 8)
        }
        return value
    }
    func subdata(in range: Range<Int>) throws -> Data {
        guard let owned else {
            // A bounded parse must capture a deferred range instead of silently
            // materializing payload through this legacy API.
            throw DICOMError.parsingFailed("Unbudgeted materialization in bounded parser")
        }
        return owned.subdata(in: owned.startIndex + range.lowerBound..<owned.startIndex + range.upperBound)
    }
    /// Decode one Unicode scalar without an input-sized String allocation. This
    /// preserves the legacy string accessor's UTF-8 validity and Unicode padding
    /// rules when selecting a bounded Transfer Syntax UID.
    func scalar(at position: inout Int, end: Int) throws -> Unicode.Scalar? {
        guard position < end else { return nil }
        let first = try byte(at: position)
        position += 1
        if first < 0x80 { return Unicode.Scalar(UInt32(first)) }
        let following: Int
        var value: UInt32
        let minimum: UInt32
        switch first {
        case 0xC2...0xDF: following = 1; value = UInt32(first & 0x1F); minimum = 0x80
        case 0xE0...0xEF: following = 2; value = UInt32(first & 0x0F); minimum = 0x800
        case 0xF0...0xF4: following = 3; value = UInt32(first & 0x07); minimum = 0x10000
        default: return nil
        }
        guard following <= end - position else { return nil }
        for _ in 0..<following {
            let continuation = try byte(at: position); position += 1
            guard continuation & 0xC0 == 0x80 else { return nil }
            value = value << 6 | UInt32(continuation & 0x3F)
        }
        guard value >= minimum else { return nil }
        return Unicode.Scalar(value)
    }

}
