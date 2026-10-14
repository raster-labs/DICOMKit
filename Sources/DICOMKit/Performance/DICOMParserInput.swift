// NEMA-verified: 2026a, checked 2026-10-14 — no DICOM-standard data (parser storage cursor).
import Foundation
import DICOMCore

/// Storage strategy only: all DICOM grammar remains in DICOMParser.
struct DICOMParserInput: ~Copyable {
    private let owned: Data?
    // The enclosing verified source/index owns and pins this borrowed view.
    private let source: VerifiedSourceView?
    private var window: DICOMByteBuffer?
    private var windowStart = -1
    private static let windowBytes = 64 * 1024
    let count: Int
    init(data: Data) { owned = data; source = nil; count = data.count }
    init(source: VerifiedSourceView) { owned = nil; self.source = source; count = source.count }

    mutating func checkpoint() -> DICOMParserOutcome<Void> {
        if let failure = source?.cancellation.failure { return .failure(.managed(failure)) }
        return .success(())
    }

    mutating func byte(at offset: Int) -> DICOMParserOutcome<UInt8> {
        guard offset >= 0, offset < count else { return .failure(.unexpectedEndOfData) }
        if let owned { return .success(owned[owned.startIndex + offset]) }
        guard let source else { return .failure(.unexpectedEndOfData) }
        let start = offset / Self.windowBytes * Self.windowBytes
        if windowStart != start {
            // Drop an obsolete immutable window before refill. No borrow escapes.
            window = nil
            windowStart = -1
            switch source.read(start..<(start + min(Self.windowBytes, count - start)), resource: .encoded) {
            case .success(let bytes): window = .some(consume bytes)
            case .failure(let failure): return .failure(.managed(failure))
            }
            windowStart = start
        }
        guard let value = window?.withBorrowedBytes({ $0[offset - start] }) else {
            return .failure(.unexpectedEndOfData)
        }
        return .success(value)
    }
    mutating func readUInt16LE(at offset: Int) -> DICOMParserOutcome<UInt16?> {
        return integer16(at: offset, little: true)
    }
    mutating func readUInt16BE(at offset: Int) -> DICOMParserOutcome<UInt16?> {
        return integer16(at: offset, little: false)
    }
    mutating func readUInt32LE(at offset: Int) -> DICOMParserOutcome<UInt32?> {
        return integer32(at: offset, little: true)
    }
    mutating func readUInt32BE(at offset: Int) -> DICOMParserOutcome<UInt32?> {
        return integer32(at: offset, little: false)
    }
    private mutating func integer16(at offset: Int, little: Bool) -> DICOMParserOutcome<UInt16?> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard offset >= 0, offset <= count, 2 <= count - offset else { return .success(nil) }
        if let owned { return .success(little ? owned.readUInt16LE(at: offset) : owned.readUInt16BE(at: offset)) }
        guard let parsedValue1 = byte(at: offset).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let parsedValue2 = byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let a = UInt16(parsedValue1), b = UInt16(parsedValue2)
        return .success(little ? a | b << 8 : a << 8 | b)
    }
    private mutating func integer32(at offset: Int, little: Bool) -> DICOMParserOutcome<UInt32?> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard offset >= 0, offset <= count, 4 <= count - offset else { return .success(nil) }
        if let owned { return .success(little ? owned.readUInt32LE(at: offset) : owned.readUInt32BE(at: offset)) }
        var value: UInt32 = 0
        for index in 0..<4 {
            guard let parsedValue1 = byte(at: offset + index).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            value |= UInt32(parsedValue1) << (little ? index * 8 : (3 - index) * 8)
        }
        return .success(value)
    }
    mutating func subdata(in range: Range<Int>) -> DICOMParserOutcome<Data> {
        guard let owned else {
            // A bounded parse must capture a deferred range instead of silently
            // materializing payload through this legacy API.
            return .failure(.unbudgetedMaterialization)
        }
        return .success(owned.subdata(in: owned.startIndex + range.lowerBound..<owned.startIndex + range.upperBound))
    }
    /// Decode one Unicode scalar without an input-sized String allocation. This
    /// preserves the legacy string accessor's UTF-8 validity and Unicode padding
    /// rules when selecting a bounded Transfer Syntax UID.
    mutating func scalar(at position: inout Int, end: Int) -> DICOMParserOutcome<Unicode.Scalar?> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard position < end else { return .success(nil) }
        guard let parsedValue1 = byte(at: position).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let first = parsedValue1
        position += 1
        if first < 0x80 { return .success(Unicode.Scalar(UInt32(first))) }
        let following: Int
        var value: UInt32
        let minimum: UInt32
        switch first {
        case 0xC2...0xDF: following = 1; value = UInt32(first & 0x1F); minimum = 0x80
        case 0xE0...0xEF: following = 2; value = UInt32(first & 0x0F); minimum = 0x800
        case 0xF0...0xF4: following = 3; value = UInt32(first & 0x07); minimum = 0x10000
        default: return .success(nil)
        }
        guard following <= end - position else { return .success(nil) }
        for _ in 0..<following {
            guard let parsedValue2 = byte(at: position).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let continuation = parsedValue2; position += 1
            guard continuation & 0xC0 == 0x80 else { return .success(nil) }
            value = value << 6 | UInt32(continuation & 0x3F)
        }
        guard value >= minimum else { return .success(nil) }
        return .success(Unicode.Scalar(value))
    }

}
