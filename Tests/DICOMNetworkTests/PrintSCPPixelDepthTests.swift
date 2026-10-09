//
// PrintSCPPixelDepthTests.swift
// DICOMNetworkTests
//
// What the printer does with an image box whose depth the standard does not
// allow.
//
// PS3.3 Table C.13-5 enumerates Bits Stored as 8 or 12 in the Basic Grayscale
// Image Sequence and fixes the Basic Color Image Sequence at 8. A sender that puts 16 in
// Bits Stored has produced a non-conformant SOP Instance, and the SCP would be
// within its rights to fail the N-SET.
//
// It does not. Every pixel that arrived is meaningful and only the label is
// wrong, so the depth is clamped, the samples are scaled to match, the film
// prints, and the log carries a warning naming the clause. These tests pin all
// four of those, because dropping any one of them turns a recoverable sender
// bug into either a failed job or a silently over-bright film.
//

import XCTest
import DICOMCore
@testable import DICOMNetwork

final class PrintSCPPixelDepthTests: XCTestCase {

    // MARK: Fixtures

    private let configuration = PrintSCPConfiguration(aeTitle: "PRINTER")

    /// A one-item pixel module carrying `bitsStored` in a `bitsAllocated`
    /// container, with every sample set to `sample`.
    private func pixelModule(
        bitsAllocated: UInt16,
        bitsStored: UInt16,
        sample: UInt16 = 0,
        rows: UInt16 = 2,
        columns: UInt16 = 2,
        samplesPerPixel: UInt16 = 1,
        photometric: String = "MONOCHROME2"
    ) -> PrintAttributeSet {
        let pixelCount = Int(rows) * Int(columns) * Int(samplesPerPixel)
        var pixels = Data()
        for _ in 0..<pixelCount {
            if bitsAllocated == 8 {
                pixels.append(UInt8(truncatingIfNeeded: sample))
            } else {
                pixels.append(UInt8(sample & 0xFF))
                pixels.append(UInt8(sample >> 8))
            }
        }

        var set = PrintAttributeSet()
        set.insert(DataElement.uint16(tag: .rows, value: rows))
        set.insert(DataElement.uint16(tag: .columns, value: columns))
        set.insert(DataElement.uint16(tag: .bitsAllocated, value: bitsAllocated))
        set.insert(DataElement.uint16(tag: .bitsStored, value: bitsStored))
        set.insert(DataElement.uint16(tag: .highBit, value: bitsStored - 1))
        set.insert(DataElement.uint16(tag: .samplesPerPixel, value: samplesPerPixel))
        set.insert(DataElement.uint16(tag: .pixelRepresentation, value: 0))
        set.insert(DataElement.string(
            tag: .photometricInterpretation, vr: .CS, value: photometric))
        set.insert(DataElement(
            tag: .pixelData, vr: .OW, length: UInt32(pixels.count), valueData: pixels))
        return set
    }

    // MARK: The resolver

    func testEnumeratedGrayscaleDepthsAreAccepted() {
        for depth in PrintPixelDepthConformance.grayscaleBitsStored {
            let resolved = PrintPixelDepthConformance.resolve(
                bitsStored: depth, bitsAllocated: 16, isColor: false)
            XCTAssertEqual(resolved.bitsStored, depth)
            XCTAssertEqual(resolved.highBit, depth - 1)
            XCTAssertTrue(resolved.notes.isEmpty, "conformant depth should say nothing")
        }
    }

    /// 12-in-16 is the legal deep-grayscale shape and must survive untouched —
    /// it is Bits *Stored* that is constrained, not Bits Allocated, and
    /// confusing the two would reject every deep film ever sent.
    func testTwelveInSixteenIsUntouched() {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 12, bitsAllocated: 16, isColor: false)
        XCTAssertEqual(resolved.bitsStored, 12)
        XCTAssertEqual(resolved.highBit, 11)
        XCTAssertTrue(resolved.notes.isEmpty)
    }

    func testSixteenBitStoredClampsToTwelve() throws {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 16, bitsAllocated: 16, isColor: false)
        XCTAssertEqual(resolved.bitsStored, 12)
        XCTAssertEqual(resolved.highBit, 11)

        let note = try XCTUnwrap(resolved.notes.first)
        // Both image sequences are enumerated in PS3.3 Table C.13-5 (Image
        // Box Pixel Presentation Module); C.13-3 is the Film Box module.
        XCTAssertTrue(note.contains("C.13-5"), note)
        XCTAssertTrue(note.contains("16"), note)
        XCTAssertTrue(note.contains("12"), note)
    }

    /// The colour box has exactly one legal depth, so anything else lands on 8.
    func testColorBoxAlwaysResolvesToEight() throws {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 16, bitsAllocated: 16, isColor: true)
        XCTAssertEqual(resolved.bitsStored, 8)
        XCTAssertEqual(resolved.highBit, 7)
        XCTAssertTrue(try XCTUnwrap(resolved.notes.first).contains("C.13-5"))
    }

    /// Bits Stored above Bits Allocated is malformed rather than over-deep: the
    /// container wins, and the operator hears about both corrections.
    func testStoredAboveAllocatedIsBoundedByTheContainer() {
        let resolved = PrintPixelDepthConformance.resolve(
            bitsStored: 12, bitsAllocated: 8, isColor: false)
        XCTAssertEqual(resolved.bitsStored, 8)
        XCTAssertEqual(resolved.highBit, 7)
        XCTAssertFalse(resolved.notes.isEmpty)
    }

    // MARK: Rescaling

    /// The correction that would be easy to forget: relabelling 16 as 12 without
    /// touching the samples makes every pixel four times too bright, so a
    /// clamped film would come out visibly wrong rather than merely shallower.
    func testClampedSamplesAreScaledNotJustRelabelled() throws {
        let item = pixelModule(bitsAllocated: 16, bitsStored: 16, sample: 0xFFFF)
        let parsed = try PrintSCPParser.parsePixelModule(
            item, isColor: false, configuration: configuration)

        XCTAssertEqual(parsed.image.bitsStored, 12)
        XCTAssertEqual(parsed.image.highBit, 11)

        // 0xFFFF at 16 bits is full scale; at 12 bits full scale is 0x0FFF.
        let first = UInt16(parsed.image.pixelData[0])
            | (UInt16(parsed.image.pixelData[1]) << 8)
        XCTAssertEqual(first, 0x0FFF)
    }

    func testRescalePreservesBufferLength() throws {
        let item = pixelModule(bitsAllocated: 16, bitsStored: 16, sample: 0x8000)
        let original = try XCTUnwrap(item.bytes(for: .pixelData))
        let parsed = try PrintSCPParser.parsePixelModule(
            item, isColor: false, configuration: configuration)
        XCTAssertEqual(parsed.image.pixelData.count, original.count)
    }

    func testConformantPixelsAreNotRewritten() throws {
        let item = pixelModule(bitsAllocated: 16, bitsStored: 12, sample: 0x0ABC)
        let original = try XCTUnwrap(item.bytes(for: .pixelData))
        let parsed = try PrintSCPParser.parsePixelModule(
            item, isColor: false, configuration: configuration)
        XCTAssertEqual(parsed.image.pixelData, original)
        XCTAssertTrue(parsed.notes.isEmpty)
    }

    // MARK: The job still prints

    /// The whole point: a non-conformant depth must not throw. An SCU that
    /// over-reached gets a film and a warning, not a failed job.
    func testNonConformantDepthDoesNotFailTheNSet() {
        let item = pixelModule(bitsAllocated: 16, bitsStored: 16)
        XCTAssertNoThrow(try PrintSCPParser.parsePixelModule(
            item, isColor: false, configuration: configuration))
    }

    /// Genuinely broken pixels are still refused — clamping the depth must not
    /// have turned the parser permissive about everything else.
    func testTruncatedPixelDataIsStillRejected() {
        var set = PrintAttributeSet()
        set.insert(DataElement.uint16(tag: .rows, value: 64))
        set.insert(DataElement.uint16(tag: .columns, value: 64))
        set.insert(DataElement.uint16(tag: .bitsAllocated, value: 16))
        set.insert(DataElement.uint16(tag: .bitsStored, value: 16))
        set.insert(DataElement.uint16(tag: .samplesPerPixel, value: 1))
        set.insert(DataElement(
            tag: .pixelData, vr: .OW, length: 4, valueData: Data([0, 0, 0, 0])))

        XCTAssertThrowsError(try PrintSCPParser.parsePixelModule(
            set, isColor: false, configuration: configuration))
    }
}
