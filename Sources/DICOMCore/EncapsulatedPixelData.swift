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
        guard frameIndex >= 0 && frameIndex < descriptor.numberOfFrames else {
            return nil
        }
        
        // Case 1: Using offset table
        if !offsetTable.isEmpty && offsetTable.count >= descriptor.numberOfFrames {
            return extractFrameUsingOffsetTable(at: frameIndex)
        }
        
        // Case 2: One fragment per frame
        if fragments.count == descriptor.numberOfFrames {
            return fragments[frameIndex]
        }
        
        // Case 3: Single-frame image - concatenate all fragments
        if descriptor.numberOfFrames == 1 && !fragments.isEmpty {
            var combined = Data()
            for fragment in fragments {
                combined.append(fragment)
            }
            return combined
        }
        
        // Case 4: Multi-frame without offset table - attempt fragment-per-frame
        if frameIndex < fragments.count {
            return fragments[frameIndex]
        }
        
        return nil
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
        let frames = descriptor.numberOfFrames
        guard frames > 0, !fragments.isEmpty else { return nil }

        // 1. Extended Offset Table: offsets point at each Item Tag, so they include
        //    the 8-byte item headers (PS3.3 C.7.6.3.1.8).
        if let eot = extendedOffsets, eot.count >= frames {
            if let map = groupFragments(byFrameStartOffsets: eot.prefix(frames).map { Int($0) },
                                        headerBytesPerFragment: 8) {
                return FrameIndex(fragmentsPerFrame: map, source: .extendedOffsetTable)
            }
            return nil // EOT present but inconsistent — fail closed
        }

        // 2. Basic Offset Table: offsets include 8-byte item headers.
        if !offsetTable.isEmpty {
            guard offsetTable.count >= frames else { return nil }
            if let map = groupFragments(byFrameStartOffsets: offsetTable.prefix(frames).map { Int($0) },
                                        headerBytesPerFragment: 8) {
                return FrameIndex(fragmentsPerFrame: map, source: .basicOffsetTable)
            }
            return nil // BOT present but inconsistent — fail closed
        }

        // 3. One fragment per frame.
        if fragments.count == frames {
            return FrameIndex(fragmentsPerFrame: (0..<frames).map { [$0] },
                              source: .oneFragmentPerFrame)
        }

        // 4. Single frame: all fragments belong to it.
        if frames == 1 {
            return FrameIndex(fragmentsPerFrame: [Array(fragments.indices)],
                              source: .singleFrame)
        }

        return nil // multi-frame, no table, fragment count mismatch — ambiguous
    }

    /// Returns one frame's codestream using a prebuilt index
    ///
    /// Copies bytes only when a frame spans multiple fragments; the common
    /// one-fragment case returns the fragment's storage directly.
    public func frameData(at frameIndex: Int, using index: FrameIndex) -> Data? {
        guard frameIndex >= 0, frameIndex < index.fragmentsPerFrame.count else { return nil }
        let parts = index.fragmentsPerFrame[frameIndex]
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return fragments[parts[0]] }
        var combined = Data(capacity: parts.reduce(0) { $0 + fragments[$1].count })
        for i in parts { combined.append(fragments[i]) }
        return combined
    }

    /// Maps frame start offsets to whole-fragment groups
    ///
    /// Walks the fragment stream once; every frame offset must land exactly on
    /// a fragment start and offsets must be strictly monotonic, else nil.
    private func groupFragments(byFrameStartOffsets offsets: [Int],
                                headerBytesPerFragment: Int) -> [[Int]]? {
        guard offsets.first == 0 else { return nil }

        // Stream offset of each fragment's payload start.
        var fragmentStarts: [Int] = []
        fragmentStarts.reserveCapacity(fragments.count)
        var cursor = 0
        for fragment in fragments {
            fragmentStarts.append(cursor)
            cursor += fragment.count + headerBytesPerFragment
        }

        var map: [[Int]] = []
        map.reserveCapacity(offsets.count)
        var fragmentCursor = 0
        for (frame, start) in offsets.enumerated() {
            if frame > 0 && start <= offsets[frame - 1] { return nil } // non-monotonic
            guard fragmentCursor < fragmentStarts.count,
                  fragmentStarts[fragmentCursor] == start else {
                return nil // offset does not land on a fragment boundary
            }
            let next = frame + 1 < offsets.count ? offsets[frame + 1] : Int.max
            var group: [Int] = []
            while fragmentCursor < fragmentStarts.count, fragmentStarts[fragmentCursor] < next {
                group.append(fragmentCursor)
                fragmentCursor += 1
            }
            guard !group.isEmpty else { return nil }
            map.append(group)
        }
        return map
    }

    // MARK: - Private Helpers
    
    /// Extracts frame data using the offset table
    private func extractFrameUsingOffsetTable(at frameIndex: Int) -> Data? {
        guard frameIndex < offsetTable.count else {
            return nil
        }
        
        // Calculate the start offset for this frame
        let startOffset = Int(offsetTable[frameIndex])
        
        // Calculate the end offset (either next frame's offset or end of data)
        let endOffset: Int
        if frameIndex + 1 < offsetTable.count {
            endOffset = Int(offsetTable[frameIndex + 1])
        } else {
            // Last frame - need to calculate total size
            var totalSize = 0
            for fragment in fragments {
                totalSize += fragment.count + 8 // Fragment data + 8 bytes for Item tag and length
            }
            endOffset = totalSize
        }
        
        // Find which fragments contain this frame's data
        var currentOffset = 0
        var frameData = Data()
        
        for fragment in fragments {
            let fragmentStart = currentOffset
            let fragmentEnd = currentOffset + fragment.count
            
            // Check if this fragment overlaps with the frame's range
            if fragmentEnd > startOffset && fragmentStart < endOffset {
                let copyStart = max(0, startOffset - fragmentStart)
                let copyEnd = min(fragment.count, endOffset - fragmentStart)
                
                if copyStart < copyEnd {
                    let startIndex = fragment.startIndex + copyStart
                    let endIndex = fragment.startIndex + copyEnd
                    frameData.append(fragment[startIndex..<endIndex])
                }
            }
            
            // Move past this fragment (accounting for Item delimiter overhead)
            currentOffset = fragmentEnd + 8
            
            // Stop if we've passed the end of this frame
            if currentOffset >= endOffset {
                break
            }
        }
        
        return frameData.isEmpty ? nil : frameData
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
