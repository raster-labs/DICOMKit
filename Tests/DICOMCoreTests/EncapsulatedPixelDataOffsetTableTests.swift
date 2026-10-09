import Foundation
import Testing
@testable import DICOMCore

/// Offset-table conventions of PS3.5 2026a §A.4 (Basic Offset Table) and PS3.3 2026a
/// C.7.6.3.1.8 (Extended Offset Table): both give the offset of each frame's Item Tag,
/// measured from the first Item Tag after the Basic Offset Table Item.
@Suite("Encapsulated pixel data offset tables")
struct EncapsulatedPixelDataOffsetTableTests {

    private let descriptor = PixelDataDescriptor(
        rows: 2, columns: 2, numberOfFrames: 3, bitsAllocated: 8, bitsStored: 8,
        highBit: 7, isSigned: false, samplesPerPixel: 1, photometricInterpretation: .monochrome2)

    /// One fragment per frame, as C.7.6.3.1.8 requires when an Extended Offset Table is present.
    private let fragments = [Data([1, 1, 1, 1]), Data([2, 2, 2, 2, 2, 2]), Data([3, 3])]

    /// Item Tag offsets: 0, 8+4, (8+4)+(8+6).
    private let itemTagOffsets: [UInt64] = [0, 12, 26]

    @Test("Extended Offset Table values are Item Tag offsets, so they include the 8-byte headers")
    func testExtendedOffsetTableIncludesHeaders() throws {
        let encapsulated = EncapsulatedPixelData(offsetTable: [], fragments: fragments, descriptor: descriptor)
        let index = try #require(encapsulated.makeFrameIndex(extendedOffsets: itemTagOffsets))
        #expect(index.source == .extendedOffsetTable)
        #expect(index.fragmentsPerFrame == [[0], [1], [2]])
        #expect(encapsulated.frameData(at: 1, using: index) == fragments[1])
    }

    @Test("A header-less Extended Offset Table (the old, wrong convention) fails closed")
    func testHeaderlessOffsetsRejected() {
        let encapsulated = EncapsulatedPixelData(offsetTable: [], fragments: fragments, descriptor: descriptor)
        #expect(encapsulated.makeFrameIndex(extendedOffsets: [0, 4, 10]) == nil)
    }

    @Test("Basic and Extended Offset Tables share the same reference point")
    func testBasicAndExtendedAgree() throws {
        let viaBasic = EncapsulatedPixelData(offsetTable: itemTagOffsets.map { UInt32($0) },
                                             fragments: fragments, descriptor: descriptor)
        let viaExtended = EncapsulatedPixelData(offsetTable: [], fragments: fragments, descriptor: descriptor)
        let basic = try #require(viaBasic.makeFrameIndex())
        let extended = try #require(viaExtended.makeFrameIndex(extendedOffsets: itemTagOffsets))
        #expect(basic.source == .basicOffsetTable)
        #expect(basic.fragmentsPerFrame == extended.fragmentsPerFrame)
    }

    @Test("The Extended Offset Table takes precedence over a Basic Offset Table")
    func testExtendedWins() throws {
        let both = EncapsulatedPixelData(offsetTable: itemTagOffsets.map { UInt32($0) },
                                         fragments: fragments, descriptor: descriptor)
        let index = try #require(both.makeFrameIndex(extendedOffsets: itemTagOffsets))
        #expect(index.source == .extendedOffsetTable)
    }
}
