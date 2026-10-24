import Foundation
import DICOMCore
import DICOMDictionary
import DICOMKit

/// Complete binary-envelope check for durable storage. Unlike permissive image
/// reading, indexing must not quietly stop at a damaged element or Pixel Data.
/// This checks boundaries/duplicates, not IOD conformance or compressed pixels.
enum StoredFileEnvelope {
    static func validate(_ file: Data, transferSyntaxUID: String) throws {
        guard let syntax = TransferSyntax.from(uid: transferSyntaxUID) else {
            throw ServerError.storageError("Unsupported stored transfer syntax: \(transferSyntaxUID)")
        }
        var meta = Walker(data: file, explicit: true, little: true)
        meta.offset = 132
        let lengthHeader = try meta.header(limit: file.count)
        guard lengthHeader.tag == Tag(group: 2, element: 0), lengthHeader.vr == .UL,
              lengthHeader.length == 4 else { throw failure("Missing File Meta Information Group Length") }
        let metaLength = try meta.u32(meta.offset, limit: file.count)
        meta.offset += 4
        let metaEnd = try meta.end(metaLength, limit: file.count)
        try meta.dataset(until: metaEnd, depth: 0, metaOnly: true)
        if meta.offset < file.count, try meta.u16(meta.offset, limit: file.count) == 2 {
            throw failure("File Meta Information extends beyond its declared boundary")
        }
        let dataset: Data
        if syntax.isDeflated {
            dataset = try DeflatedDataSet.inflate(Data(file[metaEnd...]),
                maximumOutputByteCount: ParsingOptions.defaultMaximumInflatedByteCount)
        } else { dataset = Data(file[metaEnd...]) }
        var body = Walker(data: dataset, explicit: syntax.isExplicitVR, little: syntax.byteOrder == .littleEndian)
        try body.dataset(until: dataset.count, depth: 0)
    }

    private static func failure(_ reason: String) -> ServerError { .storageError("Invalid stored DICOM envelope: \(reason)") }

    private struct Header { let tag: Tag; let vr: VR; let length: UInt32 }
    private struct Walker {
        let data: Data
        var explicit: Bool
        var little: Bool
        var offset = 0
        var elements = 0

        func u16(_ index: Int, limit: Int) throws -> UInt16 {
            guard index >= 0, index <= limit, limit <= data.count, limit - index >= 2 else { throw failure("Truncated header") }
            return little ? UInt16(data[index]) | UInt16(data[index + 1]) << 8 : UInt16(data[index]) << 8 | UInt16(data[index + 1])
        }
        func u32(_ index: Int, limit: Int) throws -> UInt32 {
            let a = UInt32(try u16(index, limit: limit)), b = UInt32(try u16(index + 2, limit: limit))
            return little ? a | b << 16 : a << 16 | b
        }
        func end(_ length: UInt32, limit: Int) throws -> Int {
            guard offset <= limit, Int(length) <= limit - offset, length % 2 == 0 else { throw failure("Truncated or odd value length at \(offset)") }
            return offset + Int(length)
        }
        mutating func header(limit: Int) throws -> Header {
            guard elements < 2_000_000 else { throw failure("Element limit exceeded") }
            elements += 1
            let tag = Tag(group: try u16(offset, limit: limit), element: try u16(offset + 2, limit: limit))
            guard tag.group != 0xFFFE else { throw failure("Unexpected item or delimiter") }
            offset += 4
            let vr: VR, length: UInt32
            if explicit {
                guard offset <= limit, limit - offset >= 2,
                      let parsed = VR(rawValue: String(decoding: data[offset..<offset + 2], as: UTF8.self)) else { throw failure("Invalid VR") }
                vr = parsed; offset += 2
                if vr.uses32BitLength {
                    guard try u16(offset, limit: limit) == 0 else { throw failure("Nonzero reserved VR bytes") }
                    length = try u32(offset + 2, limit: limit); offset += 6
                } else { length = UInt32(try u16(offset, limit: limit)); offset += 2 }
            } else {
                vr = DataElementDictionary.primaryValueRepresentation(for: tag) ?? .UN
                length = try u32(offset, limit: limit); offset += 4
            }
            return Header(tag: tag, vr: vr, length: length)
        }
        mutating func dataset(until limit: Int, depth: Int, undefinedItem: Bool = false, metaOnly: Bool = false) throws {
            guard depth <= 64 else { throw failure("Sequence depth exceeded") }
            var seen: Set<Tag> = metaOnly ? [Tag(group: 2, element: 0)] : []
            while offset < limit {
                if try u16(offset, limit: limit) == 0xFFFE {
                    guard undefinedItem, try u16(offset + 2, limit: limit) == 0xE00D,
                          try u32(offset + 4, limit: limit) == 0 else { throw failure("Unexpected dataset delimiter") }
                    offset += 8; return
                }
                let h = try header(limit: limit)
                guard seen.insert(h.tag).inserted else { throw failure("Duplicate tag \(h.tag)") }
                guard metaOnly ? h.tag.group == 2 : h.tag.group != 2 else { throw failure("Element in wrong file-meta scope") }
                if h.vr == .SQ || h.length == UInt32.max {
                    guard !metaOnly else { throw failure("Sequence in File Meta Information") }
                    let encapsulated = h.tag == .pixelData && h.length == UInt32.max
                    guard h.vr == .SQ || h.vr == .UN || encapsulated else { throw failure("Undefined length for non-sequence") }
                    let oldExplicit = explicit, oldLittle = little
                    if h.vr == .UN, h.length == UInt32.max { explicit = false; little = true }
                    try items(length: h.length, outerLimit: limit, depth: depth + 1, fragments: encapsulated)
                    explicit = oldExplicit; little = oldLittle
                } else { offset = try end(h.length, limit: limit) }
            }
            if undefinedItem { throw failure("Missing Item Delimitation Item") }
        }
        mutating func items(length: UInt32, outerLimit: Int, depth: Int, fragments: Bool) throws {
            guard depth <= 64 else { throw failure("Sequence depth exceeded") }
            let undefined = length == UInt32.max
            let limit = undefined ? outerLimit : try end(length, limit: outerLimit)
            var itemCount = 0
            while offset < limit {
                guard elements < 2_000_000 else { throw failure("Element limit exceeded") }
                elements += 1
                guard try u16(offset, limit: limit) == 0xFFFE else { throw failure("Expected Item") }
                let kind = try u16(offset + 2, limit: limit), size = try u32(offset + 4, limit: limit)
                offset += 8
                if kind == 0xE0DD {
                    guard undefined, size == 0, !fragments || itemCount > 0 else { throw failure("Invalid Sequence Delimitation Item") }
                    return
                }
                guard kind == 0xE000 else { throw failure("Invalid Item tag") }
                itemCount += 1
                if fragments {
                    guard size != UInt32.max, itemCount != 1 || size % 4 == 0 else { throw failure("Invalid encapsulated Item length") }
                    offset = try end(size, limit: limit)
                } else if size == UInt32.max {
                    try dataset(until: limit, depth: depth, undefinedItem: true)
                } else {
                    let itemEnd = try end(size, limit: limit)
                    try dataset(until: itemEnd, depth: depth)
                }
            }
            if undefined { throw failure("Missing Sequence Delimitation Item") }
        }
    }
}
