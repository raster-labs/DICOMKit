//
// PrintDatasetReader.swift
// DICOMNetwork
//
// Server-side data-set walker for the Print SCP direction.
//
// The Print SCU serializes film-session / film-box / image-box attributes with
// `DICOMWriter`; the SCP has to read them back. `DICOMNetwork` cannot depend on
// `DICOMKit` (that would drag imaging into the networking layer), so this file
// carries a small, self-contained element walk that handles both negotiated
// VRs — Explicit VR LE and Implicit VR LE — including sequences with defined
// and undefined length, and a `PixelData` value of arbitrary size.
//
// Reference: PS3.5 Section 7 (Data Element Structure), 7.5 (Nesting).
//

import Foundation
import DICOMCore
import DICOMDictionary
// NEMA-verified: 2026a, checked 2026-09-28 — delimiters (FFFE,E000/E00D/E0DD), undefined length and Explicit VR header rules checked against PS3.5 2026a §7.1 and §7.5; no other standard data

// MARK: - Errors

/// Failures raised while walking a received data set.
public enum PrintDatasetError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The data set ended in the middle of an element header or value.
    case truncated(offset: Int)
    /// An element declared a length that runs past the end of its container.
    case valueOverrunsContainer(tag: Tag, length: UInt32, offset: Int)
    /// A sequence with undefined length was never terminated.
    case unterminatedSequence(tag: Tag)
    /// Nesting exceeded the supported depth (a malformed or hostile data set).
    case nestingTooDeep(depth: Int)

    public var description: String {
        switch self {
        case .truncated(let offset):
            return "Data set truncated at offset \(offset)"
        case .valueOverrunsContainer(let tag, let length, let offset):
            return "Element \(tag) at offset \(offset) declares length \(length) beyond its container"
        case .unterminatedSequence(let tag):
            return "Sequence \(tag) has undefined length and no delimitation item"
        case .nestingTooDeep(let depth):
            return "Data set nesting exceeded \(depth) levels"
        }
    }
}

// MARK: - Attribute set

/// A parsed, flat attribute bag: one level of a received data set.
///
/// Sequences are kept separately from ordinary elements so callers can descend
/// (`items(for:)`) without re-walking bytes. Only one item per tag is expected
/// in the Print service, but the full item list is preserved.
public struct PrintAttributeSet: Sendable {
    /// Non-sequence elements, keyed by tag.
    public private(set) var elements: [Tag: DataElement] = [:]

    /// Sequence contents, keyed by the sequence tag.
    public private(set) var sequences: [Tag: [PrintAttributeSet]] = [:]

    public init() {}

    public init(elements: [Tag: DataElement], sequences: [Tag: [PrintAttributeSet]] = [:]) {
        self.elements = elements
        self.sequences = sequences
    }

    mutating func insert(_ element: DataElement) {
        elements[element.tag] = element
    }

    mutating func insert(sequence items: [PrintAttributeSet], for tag: Tag) {
        sequences[tag] = items
    }

    /// The raw element for `tag`, if present (sequences excluded).
    public subscript(tag: Tag) -> DataElement? { elements[tag] }

    /// Whether the data set carried `tag` at all (as an element or a sequence).
    public func contains(_ tag: Tag) -> Bool {
        elements[tag] != nil || sequences[tag] != nil
    }

    /// A trimmed string value: trailing NUL / space padding removed, and the
    /// first value of a multi-valued element returned.
    public func string(for tag: Tag) -> String? {
        guard let element = elements[tag] else { return nil }
        guard let raw = String(data: element.valueData, encoding: .utf8)
            ?? String(data: element.valueData, encoding: .ascii) else { return nil }
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A US/UL value, or an IS/DS string parsed as an integer.
    public func integer(for tag: Tag) -> Int? {
        guard let element = elements[tag] else { return nil }
        switch element.vr {
        case .US:
            return element.uint16Value.map(Int.init)
        case .UL:
            return element.uint32Value.map(Int.init)
        case .SS:
            return element.int16Value.map(Int.init)
        case .SL:
            return element.int32Value.map(Int.init)
        default:
            guard let text = string(for: tag) else { return nil }
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
    }

    /// A US value specifically (the print model uses US for positions/pixel module).
    public func uint16(for tag: Tag) -> UInt16? {
        guard let value = integer(for: tag), value >= 0, value <= Int(UInt16.max) else { return nil }
        return UInt16(value)
    }

    /// The raw bytes of `tag` (used for PixelData).
    public func bytes(for tag: Tag) -> Data? {
        elements[tag]?.valueData
    }

    /// The items of sequence `tag` (empty when absent).
    public func items(for tag: Tag) -> [PrintAttributeSet] {
        sequences[tag] ?? []
    }

    /// The first item of sequence `tag`, if any.
    public func firstItem(of tag: Tag) -> PrintAttributeSet? {
        sequences[tag]?.first
    }
}

// MARK: - Reader

/// Walks a DICOM data set encoded in Explicit or Implicit VR Little Endian.
///
/// Scoped to what the Print Management service actually sends: little-endian
/// only (both print transfer syntaxes are LE), no deflate, no big endian.
public struct PrintDatasetReader: Sendable {
    /// Whether the negotiated transfer syntax is Explicit VR LE.
    public let explicitVR: Bool

    /// Maximum sequence nesting accepted before the data set is rejected.
    public static let maxNestingDepth = 8

    public init(explicitVR: Bool) {
        self.explicitVR = explicitVR
    }

    /// Parses a complete data set.
    public func parse(_ data: Data) throws -> PrintAttributeSet {
        let (set, _) = try parseAttributes(
            data, from: 0, limit: data.count, undefinedLength: false, depth: 0)
        return set
    }

    /// Parses the Value Field of a sequence — its Items, without the sequence's
    /// own element header or Sequence Delimitation Item (PS3.5 7.5). Used for the
    /// raw SQ values a C-FIND response keeps (`GenericQueryResult`).
    func parseSequenceValue(_ data: Data, tag: Tag) throws -> [PrintAttributeSet] {
        try parseItems(data, from: 0, limit: data.count, undefinedLength: false, tag: tag, depth: 1).0
    }

    // MARK: Element walk

    /// Parses attributes from `start` until `limit` (defined length), or until
    /// an Item Delimitation Item when `undefinedLength` is true.
    ///
    /// - Returns: the attribute set and the offset just past the region consumed.
    private func parseAttributes(
        _ data: Data,
        from start: Int,
        limit: Int,
        undefinedLength: Bool,
        depth: Int
    ) throws -> (PrintAttributeSet, Int) {
        guard depth <= Self.maxNestingDepth else {
            throw PrintDatasetError.nestingTooDeep(depth: depth)
        }

        var set = PrintAttributeSet()
        var offset = start

        while offset + 8 <= limit {
            let group = data.le16(offset)
            let element = data.le16(offset + 2)

            // Item / delimitation tags: only meaningful inside a sequence.
            if group == 0xFFFE {
                if element == 0xE00D {
                    // Item Delimitation Item — end of an undefined-length item.
                    return (set, offset + 8)
                }
                if element == 0xE0DD {
                    // Sequence Delimitation Item — the caller consumes it.
                    return (set, offset)
                }
                // A stray Item tag at attribute level: stop rather than guess.
                return (set, offset)
            }

            let tag = Tag(group: group, element: element)
            let header = try readHeader(data, at: offset, limit: limit, tag: tag)
            let valueStart = offset + header.size

            if header.length == undefinedLengthMarker {
                // Undefined length: a sequence, or (for PixelData) encapsulated
                // fragments. Either way the content is item-delimited.
                let (items, next) = try parseItems(
                    data, from: valueStart, limit: limit, undefinedLength: true,
                    tag: tag, depth: depth + 1)
                if header.vr == .SQ {
                    set.insert(sequence: items, for: tag)
                }
                offset = next
                continue
            }

            let valueEnd = valueStart + Int(header.length)
            guard valueEnd <= limit else {
                throw PrintDatasetError.valueOverrunsContainer(
                    tag: tag, length: header.length, offset: offset)
            }

            if header.vr == .SQ {
                let (items, _) = try parseItems(
                    data, from: valueStart, limit: valueEnd, undefinedLength: false,
                    tag: tag, depth: depth + 1)
                set.insert(sequence: items, for: tag)
            } else {
                let value = data.subdata(in: (data.startIndex + valueStart)..<(data.startIndex + valueEnd))
                set.insert(DataElement(
                    tag: tag, vr: header.vr, length: header.length, valueData: value))
            }

            offset = valueEnd
        }

        if undefinedLength {
            throw PrintDatasetError.truncated(offset: offset)
        }
        return (set, offset)
    }

    /// Parses the items of a sequence.
    ///
    /// - Returns: the items and the offset just past the sequence (including the
    ///   Sequence Delimitation Item when `undefinedLength` is true).
    private func parseItems(
        _ data: Data,
        from start: Int,
        limit: Int,
        undefinedLength: Bool,
        tag: Tag,
        depth: Int
    ) throws -> ([PrintAttributeSet], Int) {
        var items: [PrintAttributeSet] = []
        var offset = start

        while offset + 8 <= limit {
            let group = data.le16(offset)
            let element = data.le16(offset + 2)
            let length = data.le32(offset + 4)

            if group == 0xFFFE && element == 0xE0DD {
                // Sequence Delimitation Item.
                return (items, offset + 8)
            }
            guard group == 0xFFFE && element == 0xE000 else {
                // Not an item: a malformed sequence. Stop at what we have.
                return (items, offset)
            }

            let itemStart = offset + 8
            if length == undefinedLengthMarker {
                let (item, next) = try parseAttributes(
                    data, from: itemStart, limit: limit, undefinedLength: true, depth: depth)
                items.append(item)
                offset = next
            } else {
                let itemEnd = itemStart + Int(length)
                guard itemEnd <= limit else {
                    throw PrintDatasetError.valueOverrunsContainer(
                        tag: tag, length: length, offset: offset)
                }
                let (item, _) = try parseAttributes(
                    data, from: itemStart, limit: itemEnd, undefinedLength: false, depth: depth)
                items.append(item)
                offset = itemEnd
            }
        }

        if undefinedLength {
            throw PrintDatasetError.unterminatedSequence(tag: tag)
        }
        return (items, offset)
    }

    // MARK: Header decoding

    private struct ElementHeader {
        let vr: VR
        let length: UInt32
        let size: Int
    }

    private func readHeader(_ data: Data, at offset: Int, limit: Int, tag: Tag) throws -> ElementHeader {
        guard offset + 8 <= limit else { throw PrintDatasetError.truncated(offset: offset) }

        guard explicitVR else {
            return ElementHeader(vr: Self.implicitVR(for: tag), length: data.le32(offset + 4), size: 8)
        }

        let vrBytes = [data[data.startIndex + offset + 4], data[data.startIndex + offset + 5]]
        guard let vrText = String(bytes: vrBytes, encoding: .ascii), let vr = VR(rawValue: vrText) else {
            // Not a recognizable VR: some SCUs mislabel private/unknown elements.
            // Fall back to the dictionary VR and an implicit-style 32-bit length,
            // which is how such elements are actually encoded in practice.
            return ElementHeader(vr: Self.implicitVR(for: tag), length: data.le32(offset + 4), size: 8)
        }

        if vr.uses32BitLength {
            guard offset + 12 <= limit else { throw PrintDatasetError.truncated(offset: offset) }
            return ElementHeader(vr: vr, length: data.le32(offset + 8), size: 12)
        }
        return ElementHeader(vr: vr, length: UInt32(data.le16(offset + 6)), size: 8)
    }

    /// The VR to assume for `tag` under Implicit VR LE.
    static func implicitVR(for tag: Tag) -> VR {
        // Group length elements are always UL.
        if tag.element == 0x0000 { return .UL }
        // PixelData is OW in the print image boxes (native, uncompressed).
        if tag == Tag(group: 0x7FE0, element: 0x0010) { return .OW }
        // Item / delimitation tags carry no value.
        if tag.group == 0xFFFE { return .UN }
        if let entry = DataElementDictionary.lookup(tag: tag), let vr = entry.vr.first {
            return vr
        }
        return .UN
    }
}

/// The DICOM undefined-length marker (PS3.5 7.1.1).
private let undefinedLengthMarker: UInt32 = 0xFFFF_FFFF

// MARK: - Little-endian primitives

private extension Data {
    /// Reads a little-endian UInt16 at a `startIndex`-relative offset.
    func le16(_ offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    /// Reads a little-endian UInt32 at a `startIndex`-relative offset.
    func le32(_ offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}
