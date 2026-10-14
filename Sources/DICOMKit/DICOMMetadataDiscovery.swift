import Foundation
import DICOMCore
import DICOMDictionary

/// A bounded, selective Part 10 discovery read. This is deliberately separate
/// from DICOMFile.read: skipped values are not decoded or semantically validated,
/// and this result must never be passed off as a complete DICOMFile.
public enum DICOMMetadataDiscovery {
    /// Logical discovery limits; these do not account for Swift runtime allocations.
    public struct Limits: Sendable {
        /// Maximum source length in bytes.
        public let maximumSourceBytes: Int
        /// Maximum parsed element headers across all visited scopes.
        public let maximumElements: Int
        /// Maximum sequence items across all visited scopes.
        public let maximumItems: Int
        /// Maximum nested sequence depth.
        public let maximumDepth: Int
        /// Maximum total bytes of retained selected values.
        public let maximumRetainedBytes: Int
        /// Maximum bytes retained for one selected value.
        public let maximumValueBytes: Int
        /// Set positive logical limits, validated when discovery starts.
        /// - Parameters:
        ///   - maximumSourceBytes: Source-length limit in bytes.
        ///   - maximumElements: Element-header count limit.
        ///   - maximumItems: Sequence-item count limit.
        ///   - maximumDepth: Nested sequence-depth limit.
        ///   - maximumRetainedBytes: Total selected-value byte limit.
        ///   - maximumValueBytes: Per-selected-value byte limit.
        public init(maximumSourceBytes: Int = 1 << 40, maximumElements: Int = 100_000,
                    maximumItems: Int = 100_000, maximumDepth: Int = 32,
                    maximumRetainedBytes: Int = 1_048_576, maximumValueBytes: Int = 4096) {
            self.maximumSourceBytes = maximumSourceBytes; self.maximumElements = maximumElements
            self.maximumItems = maximumItems; self.maximumDepth = maximumDepth
            self.maximumRetainedBytes = maximumRetainedBytes; self.maximumValueBytes = maximumValueBytes
        }
    }
    /// Discovery failures without patient values or source paths.
    public enum Failure: String, Error, Sendable {
        case invalidOptions, sourceLimit, invalidPart10, invalidStructure, truncatedInput
        case elementLimit, itemLimit, depthLimit, retainedValueLimit, unsupportedTransferSyntax
        case invalidTransferSyntax, duplicateTag, cancelled
    }
    /// Selected metadata and traversal counts, not a complete parsed DICOM file.
    public struct Result: Sendable {
        /// Retained file meta fields needed to identify and interpret the source.
        public let fileMetaInformation: DataSet
        /// Requested root elements whose values passed retention limits.
        public let selectedRootElements: DataSet
        /// Direct items of the root Directory Record Sequence only. Offset-linked
        /// hierarchy is not interpreted; callers must inspect record in-use flags.
        public let directoryRecords: [DataSet]
        /// Complete source length reported by the caller.
        public let sourceByteCount: Int
        /// Sum of bytes returned by the caller's read closure.
        public let bytesRead: Int
        /// Value bytes advanced over without acquisition.
        public let skippedValueBytes: Int
    }

    /// `reading` must return exactly the requested bytes from a stable source or
    /// throw. File acquisition/identity verification belongs to its caller.
    /// Every read is bounded; bulk data is advanced over without allocation.
    /// - Parameters:
    ///   - byteCount: Complete source length.
    ///   - rootTags: Root attributes to retain.
    ///   - limits: Logical traversal and value-retention limits.
    ///   - reading: Stable-source read closure taking byte offset and length.
    /// - Returns: Selected metadata and traversal counts, with skipped values absent.
    public static func read(byteCount: Int, retaining rootTags: Set<Tag>, limits: Limits = .init(),
                            reading: @escaping (Int, Int) throws -> Data) throws -> Result {
        var reader = Reader(size: byteCount, rootTags: rootTags, limits: limits, reading: reading)
        return try reader.run()
    }

    private struct Header {
        let tag: Tag
        let vr: VR
        let length: UInt32
    }
    private struct Reader {
        let size: Int
        let rootTags: Set<Tag>
        let limits: Limits
        let reading: (Int, Int) throws -> Data
        var offset = 0, elements = 0, items = 0, retainedBytes = 0, bytesRead = 0, skippedBytes = 0
        var records: [DataSet] = []
        var fileMetaTags: Set<Tag> { [Self.tag(0x00020000), Self.tag(0x00020002), Self.tag(0x00020003), Self.tag(0x00020010)] }
        var directoryTags: Set<Tag> { [Self.tag(0x00041410), Self.tag(0x00041430), Self.tag(0x00041500), Self.tag(0x00041510), Self.tag(0x00041511), Self.tag(0x00041512)] }

        mutating func run() throws -> Result {
            guard limits.maximumSourceBytes > 0, limits.maximumElements > 0, limits.maximumItems > 0,
                  limits.maximumDepth > 0, limits.maximumRetainedBytes > 0, limits.maximumValueBytes > 0,
                  size >= 0 else { throw Failure.invalidOptions }
            guard size <= limits.maximumSourceBytes else { throw Failure.sourceLimit }
            guard size >= 132, try read(128, 4).elementsEqual([68, 73, 67, 77]) else { throw Failure.invalidPart10 }
            offset = 132
            let groupLength = try header(explicit: true, order: .littleEndian, end: size)
            guard groupLength.tag == Self.tag(0x00020000), groupLength.vr == .UL,
                  groupLength.length == 4 else { throw Failure.invalidPart10 }
            let groupBytes = try value(groupLength, order: .littleEndian, retain: true, end: size)
            let count = Int(uint32(groupBytes.valueData, 0, .littleEndian))
            guard count <= size - offset else { throw Failure.truncatedInput }
            let metaEnd = offset + count
            var meta = [groupBytes], seen: Set<Tag> = [groupLength.tag]
            while offset < metaEnd {
                let field = try header(explicit: true, order: .littleEndian, end: metaEnd)
                guard field.tag.group == 2, field.vr != .SQ, field.length != .max else { throw Failure.invalidPart10 }
                guard seen.insert(field.tag).inserted else { throw Failure.duplicateTag }
                let element = try value(field, order: .littleEndian, retain: fileMetaTags.contains(field.tag), end: metaEnd)
                if fileMetaTags.contains(field.tag) { meta.append(element) }
            }
            guard offset == metaEnd else { throw Failure.invalidPart10 }
            let fileMeta = DataSet(elements: meta)
            guard let syntaxElement = fileMeta[Self.tag(0x00020010)], syntaxElement.vr == .UI,
                  let syntaxUID = uid(syntaxElement.valueData) else { throw Failure.invalidTransferSyntax }
            guard let syntax = TransferSyntax.from(uid: syntaxUID), !syntax.isDeflated else {
                throw Failure.unsupportedTransferSyntax
            }
            // This path understands standard native datasets and encapsulated
            // Explicit VR LE headers, never proprietary/unknown dataset encodings.
            guard syntax == .implicitVRLittleEndian || syntax == .explicitVRLittleEndian
                    || syntax == .explicitVRBigEndian
                    || (syntax.isEncapsulated && syntax.isExplicitVR && syntax.byteOrder == .littleEndian) else {
                throw Failure.unsupportedTransferSyntax
            }
            let root = try dataset(end: size, undefined: false, depth: 0, keep: rootTags,
                                   explicit: syntax.isExplicitVR, order: syntax.byteOrder,
                                   encapsulated: syntax.isEncapsulated, root: true)
            guard offset == size else { throw Failure.invalidStructure }
            return Result(fileMetaInformation: fileMeta, selectedRootElements: DataSet(elements: root),
                          directoryRecords: records, sourceByteCount: size, bytesRead: bytesRead,
                          skippedValueBytes: skippedBytes)
        }

        mutating func read(_ at: Int, _ count: Int) throws -> Data {
            if Task<Never, Never>.isCancelled { throw Failure.cancelled }
            guard at >= 0, count >= 0, at <= size, count <= size - at else { throw Failure.truncatedInput }
            let bytes = try reading(at, count)
            guard bytes.count == count else { throw Failure.truncatedInput }
            guard count <= Int.max - bytesRead else { throw Failure.sourceLimit }
            bytesRead += count
            return bytes
        }
        mutating func header(explicit: Bool, order: ByteOrder, end: Int) throws -> Header {
            guard offset <= end, end - offset >= 8 else { throw Failure.truncatedInput }
            guard elements < limits.maximumElements else { throw Failure.elementLimit }
            elements += 1
            let bytes = try read(offset, 8)
            let fieldTag = Tag(group: uint16(bytes, 0, order), element: uint16(bytes, 2, order))
            guard fieldTag.group != 0xFFFE else { throw Failure.invalidStructure }
            offset += 8
            let vr: VR, length: UInt32
            if explicit {
                guard let name = String(bytes: bytes[4..<6], encoding: .ascii), let representation = VR(rawValue: name) else {
                    throw Failure.invalidStructure
                }
                vr = representation
                if vr.uses32BitLength {
                    guard bytes[6] == 0, bytes[7] == 0, end - offset >= 4 else { throw Failure.invalidStructure }
                    length = uint32(try read(offset, 4), 0, order); offset += 4
                } else { length = UInt32(uint16(bytes, 6, order)) }
            } else {
                vr = DataElementDictionary.lookup(tag: fieldTag)?.vr.first ?? .UN
                length = uint32(bytes, 4, order)
            }
            guard length == .max || length.isMultiple(of: 2) else { throw Failure.invalidStructure }
            return Header(tag: fieldTag, vr: vr, length: length)
        }
        mutating func value(_ field: Header, order: ByteOrder, retain: Bool, end: Int) throws -> DataElement {
            guard field.length != .max, offset <= end, Int(field.length) <= end - offset else {
                throw Failure.truncatedInput
            }
            let count = Int(field.length)
            let bytes: Data
            if retain {
                guard count <= limits.maximumValueBytes, count <= limits.maximumRetainedBytes - retainedBytes else {
                    throw Failure.retainedValueLimit
                }
                retainedBytes += count
                bytes = try read(offset, count)
            } else { bytes = Data(); skippedBytes += count }
            offset += count
            return DataElement(tag: field.tag, vr: field.vr, length: field.length, valueData: bytes, byteOrder: order)
        }
        mutating func dataset(end: Int, undefined: Bool, depth: Int, keep: Set<Tag>,
                              explicit: Bool, order: ByteOrder, encapsulated: Bool, root: Bool = false) throws -> [DataElement] {
            var output: [DataElement] = [], seen = Set<Tag>()
            while offset < end {
                guard end - offset >= 8 else { throw Failure.truncatedInput }
                let marker = try read(offset, 8)
                if uint16(marker, 0, order) == 0xFFFE {
                    guard undefined, uint16(marker, 2, order) == 0xE00D,
                          uint32(marker, 4, order) == 0 else { throw Failure.invalidStructure }
                    offset += 8; return output
                }
                let field = try header(explicit: explicit, order: order, end: end)
                guard field.tag.group != 2 else { throw Failure.invalidStructure }
                guard seen.insert(field.tag).inserted else { throw Failure.duplicateTag }
                if field.vr == .SQ {
                    try sequence(field, end: end, depth: depth + 1, explicit: explicit, order: order,
                                 encapsulated: encapsulated, directory: root && field.tag == Self.tag(0x00041220))
                    if keep.contains(field.tag) {
                        output.append(DataElement(tag: field.tag, vr: field.vr, length: field.length, valueData: Data(), byteOrder: order))
                    }
                } else if field.tag == Self.tag(0x7FE00010) && encapsulated {
                    if !root, field.length != .max {
                        // PS3.5 A.4 allows native Pixel Data in nested datasets,
                        // e.g. an Icon Image Sequence under a compressed root.
                        guard field.vr == .OB || field.vr == .OW else { throw Failure.invalidStructure }
                        _ = try value(field, order: order, retain: false, end: end)
                    } else {
                        // Root Pixel Data must obey its encapsulated syntax.
                        guard field.vr == .OB, field.length == .max else { throw Failure.invalidStructure }
                        try fragments(end: end, order: order)
                    }
                } else {
                    // Undefined UN follows implicit-LE item encoding (PS3.5 6.2.2).
                    // Native undefined-length Pixel Data remains outside scope.
                    if field.length == .max, field.vr == .UN {
                        try sequence(field, end: end, depth: depth + 1, explicit: false, order: .littleEndian,
                                     encapsulated: false, directory: false)
                        if keep.contains(field.tag) {
                            output.append(DataElement(tag: field.tag, vr: field.vr, length: field.length, valueData: Data(), byteOrder: order))
                        }
                    } else {
                        guard field.length != .max else { throw Failure.invalidStructure }
                        let element = try value(field, order: order, retain: keep.contains(field.tag), end: end)
                        if keep.contains(field.tag) { output.append(element) }
                    }
                }
            }
            guard !undefined, offset == end else { throw Failure.truncatedInput }
            return output
        }
        mutating func sequence(_ field: Header, end: Int, depth: Int, explicit: Bool,
                               order: ByteOrder, encapsulated: Bool, directory: Bool) throws {
            guard depth <= limits.maximumDepth else { throw Failure.depthLimit }
            let undefined = field.length == .max
            guard undefined || Int(field.length) <= end - offset else { throw Failure.truncatedInput }
            let sequenceEnd = undefined ? end : offset + Int(field.length)
            while offset < sequenceEnd {
                guard sequenceEnd - offset >= 8 else { throw Failure.truncatedInput }
                let bytes = try read(offset, 8); offset += 8
                guard uint16(bytes, 0, order) == 0xFFFE else { throw Failure.invalidStructure }
                let element = uint16(bytes, 2, order), length = uint32(bytes, 4, order)
                if element == 0xE0DD {
                    guard undefined, length == 0 else { throw Failure.invalidStructure }
                    return
                }
                guard element == 0xE000, length == .max || length.isMultiple(of: 2) else { throw Failure.invalidStructure }
                guard items < limits.maximumItems else { throw Failure.itemLimit }; items += 1
                guard length == .max || Int(length) <= sequenceEnd - offset else { throw Failure.truncatedInput }
                let itemEnd = length == .max ? sequenceEnd : offset + Int(length)
                let fields = try dataset(end: itemEnd, undefined: length == .max, depth: depth,
                                         keep: directory ? directoryTags : [], explicit: explicit,
                                         order: order, encapsulated: encapsulated)
                if directory { records.append(DataSet(elements: fields)) }
            }
            guard !undefined, offset == sequenceEnd else { throw Failure.truncatedInput }
        }
        mutating func fragments(end: Int, order: ByteOrder) throws {
            var first = true
            while offset < end {
                guard end - offset >= 8 else { throw Failure.truncatedInput }
                let bytes = try read(offset, 8); offset += 8
                guard uint16(bytes, 0, order) == 0xFFFE else { throw Failure.invalidStructure }
                let element = uint16(bytes, 2, order), length = uint32(bytes, 4, order)
                if element == 0xE0DD {
                    guard !first, length == 0 else { throw Failure.invalidStructure }
                    return
                }
                guard element == 0xE000, length != .max, length.isMultiple(of: 2),
                      Int(length) <= end - offset else { throw Failure.invalidStructure }
                guard items < limits.maximumItems else { throw Failure.itemLimit }; items += 1
                if first { guard length.isMultiple(of: 4) else { throw Failure.invalidStructure }; first = false }
                skippedBytes += Int(length); offset += Int(length)
            }
            throw Failure.truncatedInput
        }
        static func tag(_ value: UInt32) -> Tag { Tag(group: UInt16(value >> 16), element: UInt16(value & 0xFFFF)) }
        func uint16(_ data: Data, _ at: Int, _ order: ByteOrder) -> UInt16 {
            order == .littleEndian ? UInt16(data[at]) | UInt16(data[at + 1]) << 8
                : UInt16(data[at]) << 8 | UInt16(data[at + 1])
        }
        func uint32(_ data: Data, _ at: Int, _ order: ByteOrder) -> UInt32 {
            order == .littleEndian ? UInt32(uint16(data, at, order)) | UInt32(uint16(data, at + 2, order)) << 16
                : UInt32(uint16(data, at, order)) << 16 | UInt32(uint16(data, at + 2, order))
        }
        func uid(_ data: Data) -> String? {
            guard data.count <= 64, var text = String(data: data, encoding: .ascii) else { return nil }
            if text.last == "\0" { text.removeLast() }
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) })
                && ($0.count == 1 || $0.first != "0") }) else { return nil }
            return text
        }
    }
}
