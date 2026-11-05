import Foundation

/// DICOM Encapsulated Pixel Data
///
/// Represents compressed/encapsulated pixel data extracted from a DICOM file.
/// Encapsulated pixel data consists of fragments stored in an Item/Delimiter structure.
///
/// Reference: DICOM PS3.5 Section A.4 - Transfer Syntaxes For Encapsulation of Encoded Pixel Data
///
/// NEMA-verified: 2026a, checked 2026-09-25 — Basic Offset Table semantics (offsets to each
/// frame's first Item Tag, counted from the first Item after the table) match PS3.5 2026a
/// §A.4; Extended Offset Table semantics match PS3.3 2026a C.7.6.3.1.8, which uses the same
/// reference point. The code treated Extended Offset Table values as header-less until
/// 2026-09-25, which made every conformant table fail closed; fixed.
public struct EncapsulatedPixelData: Sendable, Equatable {
    /// The Basic Offset Table containing byte offsets to each frame
    ///
    /// The offset table is stored in the first Item of the encapsulated pixel data.
    /// Each offset is a 4-byte little-endian unsigned integer.
    /// May be empty if the encoder did not provide offset information.
    ///
    /// Reference: PS3.5 Section A.4 - Table A.4-1
    public let offsetTable: [UInt32]
    
    /// The pixel data fragments
    ///
    /// Each fragment contains a portion of the compressed image data.
    /// For single-frame images, there is typically one fragment.
    /// For multi-frame images, there may be one or more fragments per frame.
    ///
    /// Reference: PS3.5 Section A.4
    public let fragments: [Data]
    
    /// Descriptor containing pixel data attributes
    public let descriptor: PixelDataDescriptor
    
    /// Creates a new EncapsulatedPixelData instance
    /// - Parameters:
    ///   - offsetTable: Byte offsets to each frame (may be empty)
    ///   - fragments: Compressed pixel data fragments
    ///   - descriptor: Pixel data descriptor
    public init(offsetTable: [UInt32], fragments: [Data], descriptor: PixelDataDescriptor) {
        self.offsetTable = offsetTable
        self.fragments = fragments
        self.descriptor = descriptor
    }
    
    // MARK: - Frame Access
    
    /// Returns the fragment data for a specific frame
    ///
    /// When an offset table is present, uses it to locate frame boundaries.
    /// When no offset table is present and there's one fragment per frame, 
    /// returns the corresponding fragment.
    /// For single-frame images with multiple fragments, concatenates all fragments.
    ///
    /// - Parameter frameIndex: Zero-based frame index
    /// - Returns: Data for the specified frame, or nil if index is out of bounds
    public func frameData(at frameIndex: Int) -> Data? {
        guard let index = makeFrameIndex() else { return nil }
        return frameData(at: frameIndex, using: index)
    }

    /// Returns all fragments as a single concatenated Data
    ///
    /// Useful for codecs that need the complete compressed stream.
    public var allFragmentData: Data {
        var combined = Data()
        for fragment in fragments {
            combined.append(fragment)
        }
        return combined
    }
    
    /// The total number of fragments
    public var fragmentCount: Int {
        fragments.count
    }
    
    /// Whether an offset table is present
    public var hasOffsetTable: Bool {
        !offsetTable.isEmpty
    }
    
    // MARK: - Frame/Fragment Index (M2)

    /// How a frame→fragment mapping was derived — reported for telemetry and
    /// used by tests to assert the expected path.
    public enum FrameIndexSource: String, Sendable {
        case extendedOffsetTable
        case basicOffsetTable
        case oneFragmentPerFrame
        case singleFrame
    }

    /// A validated frame → fragment mapping, built once and reused
    ///
    /// `fragmentsPerFrame[i]` lists the indices into `fragments` whose
    /// concatenation is frame `i`'s complete codestream. Fragment payloads are
    /// never copied during index construction.
    public struct FrameIndex: Sendable, Equatable {
        public let fragmentsPerFrame: [[Int]]
        public let source: FrameIndexSource
        fileprivate var logicalByteCounts: [Int]? = nil
    }

    /// Builds a validated frame index, failing closed on inconsistent mappings
    ///
    /// Resolution order (PS3.5 A.4 / PS3.3 C.7.6.3.1.8):
    /// 1. Extended Offset Table when supplied — 64-bit byte offsets to the first
    ///    byte of the Item Tag of each frame's fragment, measured from the first
    ///    Item Tag after the Basic Offset Table Item, so they include the 8-byte
    ///    item headers exactly as Basic Offset Table offsets do (C.7.6.3.1.8).
    /// 2. Basic Offset Table — 32-bit offsets including 8-byte item headers.
    /// 3. One fragment per frame.
    /// 4. Single frame — all fragments.
    ///
    /// Returns nil (fail closed) when offsets do not land exactly on fragment
    /// boundaries, are non-monotonic, or the counts are inconsistent — decoding
    /// the wrong frame silently is never acceptable.
    ///
    /// - Parameter extendedOffsets: values of (7FE0,0001) Extended Offset Table,
    ///   when present. Until 2026-09-25 these were wrongly treated as excluding the
    ///   item headers, so every conformant table failed closed.
    public func makeFrameIndex(extendedOffsets: [UInt64]? = nil) -> FrameIndex? {
        Self.makeFrameIndex(numberOfFrames: descriptor.numberOfFrames, fragments: fragments,
                            offsetTable: offsetTable, extendedOffsets: extendedOffsets)
    }

    private static func makeFrameIndex(numberOfFrames: Int, fragments: [Data],
                                       offsetTable: [UInt32], extendedOffsets: [UInt64]?) -> FrameIndex? {
        if extendedOffsets != nil && !offsetTable.isEmpty { return nil }
        return groupedFrameIndex(numberOfFrames: numberOfFrames, fragments: fragments,
                                 offsetCount: extendedOffsets?.count ?? offsetTable.count,
                                 offsetAt: { extendedOffsets?[$0] ?? UInt64(offsetTable[$0]) },
                                 extended: extendedOffsets != nil)
    }

    /// In-memory fragments may omit the final item pad. The shared walker takes
    /// wire lengths directly, including for the bounded parser's deferred records.
    private static func groupedFrameIndex(numberOfFrames: Int, fragments: [Data], offsetCount: Int,
                                          offsetAt: (Int) -> UInt64?, extended: Bool) -> FrameIndex? {
        guard fragments.allSatisfy({ $0.count > 0 && $0.count < Int(UInt32.max) }) else { return nil }
        var groups: [[Int]] = []
        var source = FrameIndexSource.singleFrame
        let valid = visitFrameGroups(numberOfFrames: numberOfFrames, fragmentCount: fragments.count,
            fragmentLength: { index in
                let count = fragments[index].count
                return count + count % 2
            }, offsetCount: offsetCount, offsetAt: offsetAt, extended: extended) { _, range, method in
                guard range.dropLast().allSatisfy({ fragments[$0].count % 2 == 0 }) else { return false }
                groups.append(Array(range))
                source = method
                return true
            }
        guard valid else { return nil }
        return FrameIndex(fragmentsPerFrame: groups, source: source)
    }

    /// Canonical frame grouping over fragment lengths. Both materialized and
    /// deferred storage use this walker; no duplicate offset interpretation.
    /// The visitor avoids allocating a second all-frame map for one selection.
    package static func visitFrameGroups(numberOfFrames frames: Int, fragmentCount: Int,
        fragmentLength: (Int) -> Int?, offsetCount: Int,
        offsetAt: (Int) -> UInt64?, extended: Bool,
        visit: (Int, Range<Int>, FrameIndexSource) -> Bool) -> Bool {
        guard frames > 0, fragmentCount > 0 else { return false }
        if extended && (offsetCount != frames || fragmentCount != frames) { return false }
        if offsetCount > 0 || extended {
            guard offsetCount == frames, offsetAt(0) == 0 else { return false }
            var fragment = 0, cursor = 0
            for frame in 0..<frames {
                guard let rawStart = offsetAt(frame) else { return false }
                guard rawStart <= UInt64(Int.max), Int(rawStart) == cursor,
                      fragment < fragmentCount else { return false }
                let next: Int
                if frame + 1 < frames {
                    guard let rawNext = offsetAt(frame + 1) else { return false }
                    guard rawNext <= UInt64(Int.max), rawNext > rawStart else { return false }
                    next = Int(rawNext)
                } else { next = Int.max }
                let first = fragment
                while fragment < fragmentCount, cursor < next {
                    guard let length = fragmentLength(fragment) else { return false }
                    let (size, sizeOverflow) = length.addingReportingOverflow(8)
                    let (end, endOverflow) = cursor.addingReportingOverflow(size)
                    guard length >= 0, !sizeOverflow, !endOverflow else { return false }
                    cursor = end; fragment += 1
                }
                guard fragment > first, frame + 1 == frames || cursor == next else { return false }
                guard visit(frame, first..<fragment, extended ? .extendedOffsetTable : .basicOffsetTable) else { return false }
            }
            return fragment == fragmentCount
        }
        if fragmentCount == frames {
            for frame in 0..<frames {
                guard visit(frame, frame..<frame + 1, .oneFragmentPerFrame) else { return false }
            }
            return true
        }
        if frames == 1 { return visit(0, 0..<fragmentCount, .singleFrame) }
        return false
    }

    /// Returns one frame's codestream using a prebuilt index
    ///
    /// Copies bytes only when a frame spans multiple fragments; the common
    /// one-fragment case returns the fragment's storage directly.
    public func frameData(at frameIndex: Int, using index: FrameIndex) -> Data? {
        frameData(at: frameIndex, using: index, maximumBytes: Int.max)
    }

    /// Returns the logical frame only when its entire length fits the supplied
    /// limit. Multi-fragment frames are admitted before allocating a joined buffer.
    public func frameData(at frameIndex: Int, using index: FrameIndex, maximumBytes: Int) -> Data? {
        guard maximumBytes >= 0, frameIndex >= 0, frameIndex < index.fragmentsPerFrame.count else { return nil }
        let parts = index.fragmentsPerFrame[frameIndex]
        guard !parts.isEmpty, parts.allSatisfy({ fragments.indices.contains($0) }) else { return nil }
        if parts.count == 1 {
            let fragment = fragments[parts[0]]
            let count: Int
            if let lengths = index.logicalByteCounts {
                guard lengths.indices.contains(frameIndex), lengths[frameIndex] <= fragment.count else { return nil }
                count = lengths[frameIndex]
            } else {
                count = fragment.count
            }
            guard count <= maximumBytes else { return nil }
            let bytes = count == fragment.count ? fragment : fragment.prefix(count)
            return bytes.startIndex == 0 ? bytes : Data(bytes)
        }
        var count = 0
        for part in parts {
            let (end, overflow) = count.addingReportingOverflow(fragments[part].count)
            guard !overflow, end <= maximumBytes else { return nil }
            count = end
        }
        var combined = Data(capacity: count)
        for i in parts { combined.append(fragments[i]) }
        return combined
    }

    // MARK: - Canonical Frame Resolution & Checked Offset Building (M12-02)

    /// Builds a validated frame index from raw Extended Offset Table `(7FE0,0001)`
    /// and Extended Offset Table Lengths `(7FE0,0002)` element payloads when present.
    ///
    /// Never turns a malformed Extended Offset Table or Extended Offset Table Lengths
    /// payload into an absent table; any malformed or conflicting table returns `nil`.
    public func makeFrameIndex(
        extendedOffsetTableData: Data?,
        extendedOffsetTableLengthsData: Data? = nil
    ) -> FrameIndex? {
        try? resolveFrameIndex(
            extendedOffsetTableData: extendedOffsetTableData,
            extendedOffsetTableLengthsData: extendedOffsetTableLengthsData
        )
    }

    /// Resolves a validated `FrameIndex` using canonical BOT/EOT precedence rules,
    /// distinguishing absent vs malformed `(7FE0,0001)` and `(7FE0,0002)` payloads.
    ///
    /// - Parameters:
    ///   - extendedOffsetTableData: Raw value bytes of `(7FE0,0001)` if the tag is present, or `nil` if absent.
    ///   - extendedOffsetTableLengthsData: Raw value bytes of `(7FE0,0002)` if the tag is present, or `nil` if absent.
    /// - Returns: Validated `FrameIndex`.
    /// - Throws: `EncapsulatedFrameResolutionError` when BOT/EOT tables are malformed, conflicting, or ambiguous.
    public func resolveFrameIndex(
        extendedOffsetTableData: Data? = nil,
        extendedOffsetTableLengthsData: Data? = nil
    ) throws -> FrameIndex {
        try Self.resolveFrameIndex(numberOfFrames: descriptor.numberOfFrames, fragments: fragments,
                                   offsetTable: offsetTable, extendedOffsetTableData: extendedOffsetTableData,
                                   extendedOffsetTableLengthsData: extendedOffsetTableLengthsData)
    }

    static func resolveFrameIndex(numberOfFrames: Int, fragments: [Data], offsetTable: [UInt32],
                                  extendedOffsetTableData: Data?, extendedOffsetTableLengthsData: Data?) throws -> FrameIndex {
        guard let offsets = extendedOffsetTableData else {
            guard extendedOffsetTableLengthsData == nil else {
                throw EncapsulatedFrameResolutionError.orphanExtendedOffsetTableLengths
            }
            guard let index = makeFrameIndex(numberOfFrames: numberOfFrames, fragments: fragments,
                                             offsetTable: offsetTable, extendedOffsets: nil) else {
                throw EncapsulatedFrameResolutionError.invalidFrameMapping(
                    numberOfFrames: numberOfFrames, fragmentCount: fragments.count, basicOffsetCount: offsetTable.count)
            }
            return index
        }

        guard offsetTable.isEmpty else { throw EncapsulatedFrameResolutionError.conflictingOffsetTables }
        guard !offsets.isEmpty, offsets.count % 8 == 0 else {
            throw EncapsulatedFrameResolutionError.malformedExtendedOffsetTable(byteCount: offsets.count)
        }
        guard offsets.count / 8 == numberOfFrames else {
            throw EncapsulatedFrameResolutionError.extendedOffsetTableCountMismatch(
                expected: numberOfFrames, actual: offsets.count / 8)
        }
        guard let lengths = extendedOffsetTableLengthsData else {
            throw EncapsulatedFrameResolutionError.missingExtendedOffsetTableLengths
        }
        guard !lengths.isEmpty, lengths.count % 8 == 0 else {
            throw EncapsulatedFrameResolutionError.malformedExtendedOffsetTableLengths(byteCount: lengths.count)
        }
        guard lengths.count / 8 == numberOfFrames else {
            throw EncapsulatedFrameResolutionError.extendedOffsetTableLengthsCountMismatch(
                expected: numberOfFrames, actual: lengths.count / 8)
        }
        guard fragments.count == numberOfFrames else {
            throw EncapsulatedFrameResolutionError.invalidExtendedOffsetTableBoundaries
        }
        // An Extended Offset Table has exactly one fragment per frame. Read table
        // entries in place after their byte widths and entry counts have been checked.
        guard var index = groupedFrameIndex(numberOfFrames: numberOfFrames, fragments: fragments,
                                            offsetCount: numberOfFrames,
                                            offsetAt: { tableEntry(offsets, at: $0) }, extended: true) else {
            throw EncapsulatedFrameResolutionError.invalidExtendedOffsetTableBoundaries
        }
        var logicalLengths: [Int] = []
        logicalLengths.reserveCapacity(numberOfFrames)
        for (frame, fragment) in fragments.enumerated() {
            let declared = tableEntry(lengths, at: frame)
            let actual = UInt64(fragment.count)
            let hasWirePad = actual % 2 == 0 && fragment.last == 0 && declared == actual - 1
            // A bare JPEG/JPEG 2000 end marker followed by a single zero establishes
            // that the zero is item padding. A zero alone cannot establish padding:
            // other encapsulated streams may legitimately end with zero.
            let markerPad = hasTerminalMarkerPad(fragment)
            guard declared > 0, (declared == actual && !markerPad) || hasWirePad else {
                throw EncapsulatedFrameResolutionError.conflictingExtendedOffsetTableLengths(
                    frameIndex: frame, declaredLength: declared, actualByteLength: actual)
            }
            logicalLengths.append(Int(declared))
        }
        index.logicalByteCounts = logicalLengths
        return index
    }

    private static func tableEntry(_ data: Data, at index: Int) -> UInt64 {
        let start = data.startIndex + index * 8
        var value: UInt64 = 0
        for byte in 0..<8 { value |= UInt64(data[start + byte]) << (8 * byte) }
        return value
    }

    private static func hasTerminalMarkerPad(_ data: Data) -> Bool {
        guard data.count >= 6, data.count % 2 == 0, data.last == 0,
              data[data.startIndex] == 0xff else { return false }
        let marker = data[data.startIndex + 1]
        return (marker == 0x4f || marker == 0xd8)
            && data[data.endIndex - 3] == 0xff && data[data.endIndex - 2] == 0xd9
    }

    /// Builds a validated Basic Offset Table and computes total serialized byte length
    /// using checked arithmetic for 8-byte Item headers, even-length padding, BOT size,
    /// and total encapsulated output length.
    ///
    /// - Parameters:
    ///   - fragmentLengths: Unpadded or padded byte lengths of each frame's fragment.
    ///   - includeSingleFrameOffset: When `true` and `fragmentLengths.count == 1`, emits `[0]`; when `false` and `fragmentLengths.count == 1`, emits `[]`. Multi-frame inputs (`count > 1`) always emit one offset per frame.
    ///   - maxSerializedBytes: Finite upper bound on the total serialized `(7FE0,0010)` element byte count (defaults to `Int(UInt32.max)`).
    /// - Returns: Tuple of `(offsets, totalSerializedBytes)` where `totalSerializedBytes` includes the 12-byte `(7FE0,0010)` header, 8-byte BOT item header + BOT payload, all fragment item headers + even-padded payloads, and 8-byte Sequence Delimitation Item.
    /// - Throws: `EncapsulatedOffsetBuildError` before allocating the output offset table if any length or offset overflows or exceeds bounds.
    public static func buildCheckedBasicOffsetTable(
        forFragmentLengths fragmentLengths: [Int],
        includeSingleFrameOffset: Bool = false,
        maxSerializedBytes: Int = Int(UInt32.max)
    ) throws -> (offsets: [UInt32], totalSerializedBytes: Int) {
        try buildCheckedBasicOffsetTable(lengths: fragmentLengths, includeSingleFrameOffset: includeSingleFrameOffset,
                                         maxSerializedBytes: maxSerializedBytes)
    }

    package static func buildCheckedBasicOffsetTable<Lengths: Collection>(
        lengths: Lengths, includeSingleFrameOffset: Bool, maxSerializedBytes: Int
    ) throws -> (offsets: [UInt32], totalSerializedBytes: Int) where Lengths.Element == Int {
        let emitOffsets = lengths.count > 1 || (lengths.count == 1 && includeSingleFrameOffset)
        let layout = try checkedEncapsulatedLayout(fragmentLengths: lengths,
            offsetTableCount: emitOffsets ? lengths.count : 0, checkFrameOffsets: emitOffsets,
            maxSerializedBytes: maxSerializedBytes)
        guard emitOffsets else { return ([], layout.totalElementByteCount) }

        // The same immutable input was checked for representable offsets, padded
        // item spans and the full serialized size before this allocation.
        var offsets: [UInt32] = []
        offsets.reserveCapacity(lengths.count)
        var cursor: UInt64 = 0
        for length in lengths {
            offsets.append(UInt32(cursor))
            cursor += UInt64(8 + length + length % 2)
        }
        return (offsets, layout.totalElementByteCount)
    }

    /// Convenience overload of `buildCheckedBasicOffsetTable` for `[Data]` fragments.
    public static func buildCheckedBasicOffsetTable(
        for fragments: [Data],
        includeSingleFrameOffset: Bool = false,
        maxSerializedBytes: Int = Int(UInt32.max)
    ) throws -> (offsets: [UInt32], totalSerializedBytes: Int) {
        try buildCheckedBasicOffsetTable(
            lengths: fragments.lazy.map(\.count),
            includeSingleFrameOffset: includeSingleFrameOffset,
            maxSerializedBytes: maxSerializedBytes
        )
    }

    /// Validates that an existing fragment list and Basic Offset Table can be serialized
    /// within checked 32-bit DICOM Item and total encapsulated size bounds.
    public static func validateCheckedEncapsulatedSerialization(
        fragmentLengths: [Int],
        offsetTableCount: Int,
        maxSerializedBytes: Int = Int(UInt32.max)
    ) throws -> (botByteCount: Int, valueFieldByteCount: Int, totalElementByteCount: Int) {
        try checkedEncapsulatedLayout(fragmentLengths: fragmentLengths, offsetTableCount: offsetTableCount,
                                      checkFrameOffsets: false, maxSerializedBytes: maxSerializedBytes)
    }

    static func validateCheckedEncapsulatedSerialization(
        fragments: [Data], offsetTableCount: Int, maxSerializedBytes: Int
    ) throws -> (botByteCount: Int, valueFieldByteCount: Int, totalElementByteCount: Int) {
        try checkedEncapsulatedLayout(fragmentLengths: fragments.lazy.map(\.count), offsetTableCount: offsetTableCount,
                                      checkFrameOffsets: false, maxSerializedBytes: maxSerializedBytes)
    }

    private static func checkedEncapsulatedLayout<Lengths: Collection>(
        fragmentLengths: Lengths, offsetTableCount: Int, checkFrameOffsets: Bool, maxSerializedBytes: Int
    ) throws -> (botByteCount: Int, valueFieldByteCount: Int, totalElementByteCount: Int) where Lengths.Element == Int {
        guard maxSerializedBytes >= 28 else {
            throw EncapsulatedOffsetBuildError.totalSerializedLengthOutOfBounds(
                totalBytes: 28,
                maximumAllowedBytes: maxSerializedBytes
            )
        }
        guard !fragmentLengths.isEmpty else { throw EncapsulatedOffsetBuildError.emptyFragments }
        guard offsetTableCount >= 0 else {
            throw EncapsulatedOffsetBuildError.basicOffsetTableSizeOverflow(entryCount: offsetTableCount)
        }
        let (botByteCount, botOverflow) = offsetTableCount.multipliedReportingOverflow(by: 4)
        guard !botOverflow,
              let botBytes32 = UInt32(exactly: botByteCount),
              botBytes32 != 0xFFFF_FFFF else {
            throw EncapsulatedOffsetBuildError.basicOffsetTableSizeOverflow(entryCount: offsetTableCount)
        }

        var runningFragmentItemsBytes: UInt64 = 0
        for (index, rawLength) in fragmentLengths.enumerated() {
            guard rawLength >= 0 else {
                throw EncapsulatedOffsetBuildError.negativeFragmentLength(fragmentIndex: index, length: rawLength)
            }
            guard rawLength > 0 else {
                throw EncapsulatedOffsetBuildError.fragmentLengthOutOfBounds(fragmentIndex: index, length: rawLength)
            }
            let (paddedLength, padOverflow) = rawLength.addingReportingOverflow(rawLength % 2)
            let (itemSpan, spanOverflow) = paddedLength.addingReportingOverflow(8)
            guard !padOverflow,
                  !spanOverflow,
                  let padded32 = UInt32(exactly: paddedLength),
                  padded32 != 0xFFFF_FFFF else {
                throw EncapsulatedOffsetBuildError.fragmentLengthOutOfBounds(fragmentIndex: index, length: rawLength)
            }
            if checkFrameOffsets && runningFragmentItemsBytes >= UInt64(UInt32.max) {
                throw EncapsulatedOffsetBuildError.basicOffsetTableOffsetOverflow(
                    frameIndex: index, offset: runningFragmentItemsBytes)
            }
            let (nextBytes, nextOverflow) = runningFragmentItemsBytes.addingReportingOverflow(UInt64(itemSpan))
            guard !nextOverflow else {
                throw EncapsulatedOffsetBuildError.totalSerializedLengthOutOfBounds(
                    totalBytes: UInt64.max,
                    maximumAllowedBytes: maxSerializedBytes
                )
            }
            runningFragmentItemsBytes = nextBytes
        }

        // Value field = 8 (BOT item header) + botByteCount + runningFragmentItemsBytes + 8 (Sequence Delimiter)
        let (valueWithDelimiters, vOverflow1) = runningFragmentItemsBytes.addingReportingOverflow(16)
        let (valueFieldBytes64, vOverflow2) = valueWithDelimiters.addingReportingOverflow(UInt64(botByteCount))
        let (totalElementBytes64, tOverflow) = valueFieldBytes64.addingReportingOverflow(12)
        guard !vOverflow1,
              !vOverflow2,
              !tOverflow,
              let valueFieldByteCount = Int(exactly: valueFieldBytes64),
              let totalElementByteCount = Int(exactly: totalElementBytes64),
              totalElementByteCount <= maxSerializedBytes else {
            throw EncapsulatedOffsetBuildError.totalSerializedLengthOutOfBounds(
                totalBytes: (vOverflow1 || vOverflow2 || tOverflow) ? UInt64.max : totalElementBytes64,
                maximumAllowedBytes: maxSerializedBytes
            )
        }

        return (botByteCount, valueFieldByteCount, totalElementByteCount)
    }
}

/// Errors thrown when resolving canonical frames from encapsulated pixel data.
public enum EncapsulatedFrameResolutionError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Both Basic Offset Table and Extended Offset Table carry offsets.
    case conflictingOffsetTables
    /// Extended Offset Table Lengths `(7FE0,0002)` is present without Extended Offset Table `(7FE0,0001)`.
    case orphanExtendedOffsetTableLengths
    case missingExtendedOffsetTableLengths
    /// Extended Offset Table `(7FE0,0001)` is present but empty or not a multiple of 8 bytes.
    case malformedExtendedOffsetTable(byteCount: Int)
    /// Extended Offset Table `(7FE0,0001)` entry count does not match `numberOfFrames`.
    case extendedOffsetTableCountMismatch(expected: Int, actual: Int)
    /// Extended Offset Table `(7FE0,0001)` offsets do not land on valid fragment boundaries.
    case invalidExtendedOffsetTableBoundaries
    /// Extended Offset Table Lengths `(7FE0,0002)` is present but empty or not a multiple of 8 bytes.
    case malformedExtendedOffsetTableLengths(byteCount: Int)
    /// Extended Offset Table Lengths `(7FE0,0002)` entry count does not match `numberOfFrames`.
    case extendedOffsetTableLengthsCountMismatch(expected: Int, actual: Int)
    /// Extended Offset Table Lengths `(7FE0,0002)` value for a frame conflicts with the resolved fragment byte length.
    case conflictingExtendedOffsetTableLengths(frameIndex: Int, declaredLength: UInt64, actualByteLength: UInt64)
    /// Basic Offset Table or implicit fragment-to-frame mapping is inconsistent or ambiguous.
    case invalidFrameMapping(numberOfFrames: Int, fragmentCount: Int, basicOffsetCount: Int)
    /// Extracting the resolved frame bytes failed.
    case frameExtractionFailed(frameIndex: Int)

    public var description: String {
        switch self {
        case .conflictingOffsetTables:
            return "Basic Offset Table and Extended Offset Table (7FE0,0001) cannot both be populated"
        case .missingExtendedOffsetTableLengths:
            return "Extended Offset Table (7FE0,0001) requires Extended Offset Table Lengths (7FE0,0002)"
        case .orphanExtendedOffsetTableLengths:
            return "Extended Offset Table Lengths (7FE0,0002) is present without Extended Offset Table (7FE0,0001)"
        case .malformedExtendedOffsetTable(let bytes):
            return "Malformed Extended Offset Table (7FE0,0001): byte length \(bytes) is empty or not a multiple of 8"
        case .extendedOffsetTableCountMismatch(let expected, let actual):
            return "Extended Offset Table (7FE0,0001) entry count (\(actual)) does not match Number of Frames (\(expected))"
        case .invalidExtendedOffsetTableBoundaries:
            return "Extended Offset Table (7FE0,0001) offsets do not align with encapsulated fragment boundaries"
        case .malformedExtendedOffsetTableLengths(let bytes):
            return "Malformed Extended Offset Table Lengths (7FE0,0002): byte length \(bytes) is empty or not a multiple of 8"
        case .extendedOffsetTableLengthsCountMismatch(let expected, let actual):
            return "Extended Offset Table Lengths (7FE0,0002) entry count (\(actual)) does not match Number of Frames (\(expected))"
        case .conflictingExtendedOffsetTableLengths(let frame, let declared, let actual):
            return "Extended Offset Table Lengths (7FE0,0002) for frame \(frame) (\(declared) bytes) conflicts with fragment payload (\(actual) bytes)"
        case .invalidFrameMapping(let frames, let fragments, let botCount):
            return "Ambiguous or inconsistent encapsulated frame mapping (frames: \(frames), fragments: \(fragments), BOT entries: \(botCount))"
        case .frameExtractionFailed(let frame):
            return "Failed to extract encapsulated codestream for frame \(frame)"
        }
    }
}

/// Errors thrown when building or serializing an encapsulated pixel data Basic Offset Table
/// or item stream whose lengths/offsets overflow or exceed representable bounds.
public enum EncapsulatedOffsetBuildError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A fragment has a negative byte length.
    case negativeFragmentLength(fragmentIndex: Int, length: Int)
    case emptyFragments
    case invalidNumberOfFrames
    case sequenceLengthOutOfBounds
    /// A fragment's padded length or item span overflows integer or 32-bit item length bounds.
    case fragmentLengthOutOfBounds(fragmentIndex: Int, length: Int)
    /// A frame offset in the Basic Offset Table exceeds UInt32.max (or 0xFFFF_FFFE).
    case basicOffsetTableOffsetOverflow(frameIndex: Int, offset: UInt64)
    /// The Basic Offset Table item length (numberOfFrames * 4) exceeds UInt32 bounds.
    case basicOffsetTableSizeOverflow(entryCount: Int)
    /// The total serialized encapsulated pixel data byte length overflows Int or exceeds the configured instance cap.
    case totalSerializedLengthOutOfBounds(totalBytes: UInt64, maximumAllowedBytes: Int)

    public var description: String {
        switch self {
        case .emptyFragments:
            return "Encapsulated Pixel Data has no fragments"
        case .invalidNumberOfFrames:
            return "Invalid Number of Frames for encapsulated Pixel Data"
        case .sequenceLengthOutOfBounds:
            return "Defined sequence or item length exceeds the DICOM Value Length limit"
        case .negativeFragmentLength(let index, let length):
            return "Negative encapsulated fragment length (\(length)) at fragment \(index)"
        case .fragmentLengthOutOfBounds(let index, let length):
            return "Encapsulated fragment length (\(length)) at fragment \(index) exceeds 32-bit DICOM Item bounds"
        case .basicOffsetTableOffsetOverflow(let index, let offset):
            return "Basic Offset Table offset (\(offset)) at frame \(index) exceeds 32-bit unsigned integer bounds"
        case .basicOffsetTableSizeOverflow(let count):
            return "Basic Offset Table entry count (\(count)) overflows 32-bit Item byte length"
        case .totalSerializedLengthOutOfBounds(let total, let maxAllowed):
            return "Total serialized encapsulated Pixel Data size (\(total) bytes) exceeds representable limit (\(maxAllowed) bytes)"
        }
    }
}

// MARK: - Encapsulated Pixel Data Fragment

/// A single fragment of encapsulated pixel data
///
/// Reference: PS3.5 Section A.4
public struct PixelDataFragment: Sendable, Equatable {
    /// The raw fragment data
    public let data: Data
    
    /// Creates a new fragment
    /// - Parameter data: The fragment data
    public init(data: Data) {
        self.data = data
    }
}
