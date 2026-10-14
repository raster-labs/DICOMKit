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
        if extendedOffsets != nil && !offsetTable.isEmpty { return nil }
        var groups: [[Int]] = []
        var source = FrameIndexSource.singleFrame
        let valid = Self.visitFrameGroups(numberOfFrames: descriptor.numberOfFrames,
            fragmentCount: fragments.count, fragmentLength: { fragments[$0].count },
            offsetCount: extendedOffsets?.count ?? offsetTable.count,
            offsetAt: { index in extendedOffsets?[index] ?? UInt64(offsetTable[index]) },
            extended: extendedOffsets != nil) { _, range, method in
                groups.append(Array(range)); source = method; return true
            }
        guard valid == true else { return nil }
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
        guard frameIndex >= 0, frameIndex < index.fragmentsPerFrame.count else { return nil }
        let parts = index.fragmentsPerFrame[frameIndex]
        guard !parts.isEmpty, parts.allSatisfy({ fragments.indices.contains($0) }) else { return nil }
        if parts.count == 1 { return fragments[parts[0]] }
        var combined = Data(capacity: parts.reduce(0) { $0 + fragments[$1].count })
        for i in parts { combined.append(fragments[i]) }
        return combined
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
