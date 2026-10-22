import Testing
import Foundation
@testable import DICOMCore

/// Regression tests for bugs found in the 2026-07-18 review (see BUG_REVIEW.md).
/// Each test reproduces the exact malformed input that previously crashed or
/// produced wrong output, and asserts the fixed behavior.
@Suite("Bug Regression Tests")
struct BugRegressionTests {

    // MARK: - H2: crash on malformed encapsulated pixel data

    @Test("H2: oversized encapsulated fragment length does not trap")
    func testEncapsulatedFragmentOverflowDoesNotCrash() {
        // Implicit VR LE dataset containing a Pixel Data element (7FE0,0010)
        // with undefined length, an empty Basic Offset Table, and a fragment
        // item whose declared length (0xFFFFFFFF) far exceeds the bytes present.
        var dataSet = Data()
        dataSet.append(contentsOf: [0xE0, 0x7F, 0x10, 0x00]) // (7FE0,0010) tag, LE
        dataSet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF]) // undefined length
        // Basic Offset Table item (FFFE,E000), length 0
        dataSet.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        dataSet.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // Fragment item (FFFE,E000), corrupt length 0xFFFFFFFF (exceeds remaining)
        dataSet.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        dataSet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])

        let converter = TransferSyntaxConverter()
        // Before the fix this trapped in Data.subdata(in:) and crashed the
        // process. It must now complete — returning or throwing — without trapping.
        _ = try? converter.transcode(
            dataSetData: dataSet,
            from: .implicitVRLittleEndian,
            to: .explicitVRLittleEndian
        )
        #expect(Bool(true), "transcode returned without trapping on the malformed fragment length")
    }

    // MARK: - H3: crash parsing empty / dot-only TM value

    @Test("H3: empty and dot-only TM values parse to nil without crashing")
    func testEmptyTimeValueDoesNotCrash() {
        #expect(DICOMTime.parse("") == nil)
        #expect(DICOMTime.parse(".") == nil)
        #expect(DICOMTime.parse("..") == nil)
        #expect(DICOMTime.parse(":") == nil) // no complete hour component

        // Reached via DataElement.timeValue on a zero-length TM element.
        let emptyTM = DataElement(tag: Tag(group: 0x0008, element: 0x0030), vr: .TM, length: 0, valueData: Data())
        #expect(emptyTM.timeValue == nil)

        // A valid TM must still parse correctly.
        let valid = DICOMTime.parse("1230")
        #expect(valid?.hour == 12)
        #expect(valid?.minute == 30)
    }

    // MARK: - M3: crash on duplicate tags within a sequence item

    @Test("M3: duplicate tags in a sequence item do not trap; last value wins")
    func testDuplicateTagsInSequenceItem() {
        let tag = Tag(group: 0x0008, element: 0x0018)
        let first = DataElement(tag: tag, vr: .LO, length: 4, valueData: Data("AAAA".utf8))
        let second = DataElement(tag: tag, vr: .LO, length: 4, valueData: Data("BBBB".utf8))

        // Before the fix Dictionary(uniqueKeysWithValues:) trapped on the
        // duplicate key. It must now build one entry keeping the last occurrence.
        let item = SequenceItem(elements: [first, second])
        #expect(item.elements.count == 1)
        #expect(item[tag]?.stringValue == "BBBB")
    }

    // MARK: - M2: VR AT corrupted on cross-endian transcode

    @Test("M2: AT element transcodes LE→BE as two independent UInt16s")
    func testAttributeTagEndianTranscode() throws {
        // Explicit VR LE dataset with one AT element (0028,0009) whose value is
        // the attribute tag (0018,1063), stored as group then element (LE).
        var src = Data()
        src.append(contentsOf: [0x28, 0x00, 0x09, 0x00]) // (0028,0009) tag, LE
        src.append(contentsOf: Array("AT".utf8))          // VR
        src.append(contentsOf: [0x04, 0x00])              // length 4 (short form)
        src.append(contentsOf: [0x18, 0x00, 0x63, 0x10])  // AT value (0018,1063), LE

        let converter = TransferSyntaxConverter()
        let result = try converter.transcode(
            dataSetData: src,
            from: .explicitVRLittleEndian,
            to: .explicitVRBigEndian
        )
        let out = [UInt8](result.data)

        // Correct BE encoding: group big-endian (00 18) then element (10 63).
        #expect(containsSubsequence(out, [0x00, 0x18, 0x10, 0x63]),
                "AT value should be two independent UInt16s byte-swapped in place")
        // The old 32-bit-swap bug produced this instead.
        #expect(!containsSubsequence(out, [0x10, 0x63, 0x00, 0x18]),
                "AT value must not be reversed as a single 32-bit word")
    }

    // MARK: - Helpers

    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<start + needle.count]) == needle { return true }
        }
        return false
    }
}
