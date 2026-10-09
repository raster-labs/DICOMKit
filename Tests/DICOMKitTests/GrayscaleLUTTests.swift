// GrayscaleLUTTests.swift
// DICOMKitTests
//
// SRS FR-004: table-form Modality and VOI LUTs.
//
// The decoding rules under test are the classic failure points: a declared
// entry count of 0 means 65536, the first mapped value turns signed with the
// pixels, and 8-bit entries may arrive one per byte or one per word.
//
// Expectations checked against PS3.3 2026a C.11.1.1.1 and C.11.2.1.1 (D51,
// 2026-09-30). The VOI output range is 0...2^n - 1 with n the third LUT
// Descriptor value (C.11.2.1.1); since D53 (2026-09-30) GrayscaleLUT.normalized
// uses it by default and divides by the entries' actual span only when asked
// (normalizeToUsedRange: true, the print tolerance).

import Testing
@testable import DICOMKit
import DICOMCore
import Foundation

@Suite("Grayscale LUT Tests")
struct GrayscaleLUTTests {

    // MARK: Builders

    private func descriptorData(entries: UInt16, first: UInt16, bits: UInt16) -> Data {
        var data = Data()
        for value in [entries, first, bits] {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8))
        }
        return data
    }

    private func wordData(_ values: [UInt16]) -> Data {
        var data = Data(capacity: values.count * 2)
        for value in values {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8))
        }
        return data
    }

    private func element(_ tag: DICOMCore.Tag, vr: VR, _ data: Data) -> DataElement {
        DataElement(tag: tag, vr: vr, length: UInt32(data.count), valueData: data)
    }

    private func lutItem(entries: UInt16, first: UInt16, bits: UInt16,
                         data: Data) -> SequenceItem {
        SequenceItem(elements: [
            element(DICOMCore.Tag(group: 0x0028, element: 0x3002), vr: .US,
                    descriptorData(entries: entries, first: first, bits: bits)),
            element(DICOMCore.Tag(group: 0x0028, element: 0x3006), vr: .OW, data),
        ])
    }

    // MARK: Decoding

    @Test("A word-per-entry table decodes and clamps at both ends")
    func testBasicDecodeAndClamp() throws {
        // PS3.3 C.11.1.1.1: values below the first mapped value go to the first
        // entry, values >= entries + first mapped to the last.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 4, first: 100, bits: 16,
                          data: wordData([10, 20, 30, 40])),
            signedPixels: false))
        #expect(lut.entries == [10, 20, 30, 40])
        #expect(lut.value(for: 100) == 10)
        #expect(lut.value(for: 103) == 40)
        #expect(lut.value(for: 0) == 10, "below the first mapped value clamps low")
        #expect(lut.value(for: 5000) == 40, "past the end clamps high")
    }

    @Test("Non-finite and huge inputs clamp to the table's ends instead of trapping (D54)")
    func testNonFiniteInputs() throws {
        let lut = try #require(GrayscaleLUT(firstMappedValue: 100, bitsPerEntry: 16, entries: [10, 20, 30, 40]))
        #expect(lut.entry(for: .nan) == 10)
        #expect(lut.entry(for: -.infinity) == 10)
        #expect(lut.entry(for: .infinity) == 40)
        #expect(lut.entry(for: 1e300) == 40)
        #expect(lut.entry(for: -1e300) == 10)
        #expect(lut.value(for: .nan) == 10)
        #expect(abs(lut.normalized(.infinity) - 40.0 / 65535.0) < 1e-12)
        #expect(lut.normalized(.infinity, normalizeToUsedRange: true) == 1)
        // Finite inputs keep rounding to the nearest entry and clamping at both ends
        #expect(lut.entry(for: 99.4) == 10)
        #expect(lut.entry(for: 100.5) == 20)
        #expect(lut.entry(for: 102.49) == 30)
        #expect(lut.entry(for: 102.5) == 40)
        #expect(lut.entry(for: 103) == 40)
        #expect(lut.entry(for: 104) == 40)
        let single = try #require(GrayscaleLUT(firstMappedValue: -5, bitsPerEntry: 8, entries: [7]))
        #expect(single.entry(for: .nan) == 7)
        #expect(single.entry(for: .infinity) == 7)
        #expect(single.entry(for: -5) == 7)
    }

    @Test("A declared entry count of zero means 65536, not an empty table")
    func testZeroMeans65536() throws {
        // PS3.3 C.11.1.1.1 / C.11.2.1.1: 2^16 entries are declared as 0.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 0, first: 0, bits: 16,
                          data: wordData([UInt16](repeating: 7, count: 65536))),
            signedPixels: false))
        #expect(lut.entries.count == 65536)
    }

    @Test("The first mapped value is signed when the pixels are")
    func testSignedFirstMapped() throws {
        // PS3.3 C.11.1.1.1: the second Value is US or SS per Pixel Representation.
        // 0xFC00 is −1024 as Int16 — the CT case.
        let signed = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 2, first: 0xFC00, bits: 16, data: wordData([1, 2])),
            signedPixels: true))
        #expect(signed.firstMappedValue == -1024)
        #expect(signed.value(for: -1024) == 1)

        let unsigned = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 2, first: 0xFC00, bits: 16, data: wordData([1, 2])),
            signedPixels: false))
        #expect(unsigned.firstMappedValue == 64512)
    }

    @Test("8-bit entries packed one per byte decode")
    func testBytePackedEntries() throws {
        // PS3.3 C.11.1.1.1: 8-bit entries are stored as 8 bits allocated, so the
        // Value Length equals the number of entries.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 3, first: 0, bits: 8, data: Data([5, 6, 7])),
            signedPixels: false))
        #expect(lut.entries == [5, 6, 7])
    }

    @Test("Truncated LUT data is rejected, not read past its end")
    func testTruncatedData() {
        #expect(GrayscaleLUT.parse(
            item: lutItem(entries: 100, first: 0, bits: 16, data: wordData([1, 2])),
            signedPixels: false) == nil)
    }

    // MARK: Normalization

    @Test("A table spanning its declared range normalizes over 0...2^n - 1")
    func testNormalizationFullRange() throws {
        // PS3.3 C.11.2.1.1: "The output range is from 0 to 2^n-1 where n is the
        // third Value of LUT Descriptor." A table whose entries reach 0 and
        // 2^n - 1 normalizes the same under the standard and under the
        // library's actual-range division.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 3, first: 0, bits: 16,
                          data: wordData([0, 32768, 65535])),
            signedPixels: false))
        #expect(lut.normalized(0) == 0)
        #expect(lut.normalized(2) == 1)
        #expect(abs(lut.normalized(1) - 32768.0 / 65535.0) < 1e-9)
        #expect(lut.normalized(-5) == 0, "below the first mapped value clamps to the first entry")
        #expect(lut.normalized(99) == 1, "past the end clamps to the last entry")
    }

    @Test("VOI output is normalized over 0...2^n - 1, not the entries' span")
    func testNormalizationUsesDeclaredRange() throws {
        // A table declared as 16 bits per entry whose entries stop at 4095:
        // PS3.3 C.11.2.1.1 gives it the output range 0...65535, so its last
        // entry is 4095/65535 of full white, not full white.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 3, first: 0, bits: 16,
                          data: wordData([0, 2048, 4095])),
            signedPixels: false))
        #expect(lut.normalized(0) == 0)
        #expect(abs(lut.normalized(2) - 4095.0 / 65535.0) < 1e-9)
        #expect(abs(lut.normalized(1) - 2048.0 / 65535.0) < 1e-9)
    }

    @Test("A flat table normalizes to its entry over 0...2^n - 1")
    func testFlatTable() throws {
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 2, first: 0, bits: 16, data: wordData([9, 9])),
            signedPixels: false))
        #expect(abs(lut.normalized(0) - 9.0 / 65535.0) < 1e-12)
        #expect(abs(lut.normalized(1) - 9.0 / 65535.0) < 1e-12)
    }

    @Test("normalizeToUsedRange reproduces the pre-D53 used-range scaling")
    func testUsedRangeOptIn() throws {
        // The print tolerance (FR-004): divide over the entries' actual span.
        // These are the values normalized(_:) returned before D53.
        let lut = try #require(GrayscaleLUT.parse(
            item: lutItem(entries: 3, first: 0, bits: 16,
                          data: wordData([0, 2048, 4095])),
            signedPixels: false))
        #expect(lut.normalized(0, normalizeToUsedRange: true) == 0)
        #expect(lut.normalized(2, normalizeToUsedRange: true) == 1)
        #expect(abs(lut.normalized(1, normalizeToUsedRange: true) - 2048.0 / 4095.0) < 1e-12)
        let offset = try #require(GrayscaleLUT(
            firstMappedValue: 0, bitsPerEntry: 8, entries: [10, 20, 30]))
        #expect(offset.normalized(0, normalizeToUsedRange: true) == 0)
        #expect(offset.normalized(1, normalizeToUsedRange: true) == 0.5)
        #expect(abs(offset.normalized(1) - 20.0 / 255.0) < 1e-12, "the default is the standard 0...2^n - 1 range")
        let flat = try #require(GrayscaleLUT(
            firstMappedValue: 0, bitsPerEntry: 16, entries: [9, 9]))
        #expect(flat.normalized(0, normalizeToUsedRange: true) == 0, "a flat table has no span to divide by")
    }

    // MARK: Reading from a data set

    private func sequenceElement(_ tag: DICOMCore.Tag, item: SequenceItem) -> DataElement {
        DataElement(tag: tag, vr: .SQ, length: 0, valueData: Data(),
                    sequenceItems: [item])
    }

    private func decimalElement(_ tag: DICOMCore.Tag, _ value: String) -> DataElement {
        let padded = value.count % 2 == 0 ? value : value + " "
        return DataElement(tag: tag, vr: .DS, length: UInt32(padded.utf8.count),
                           valueData: Data(padded.utf8))
    }

    @Test("A data set's Modality LUT Sequence is found and decoded")
    func testDataSetModalityLUT() throws {
        let dataSet = DataSet(elements: [
            sequenceElement(DICOMCore.Tag(group: 0x0028, element: 0x3000),
                            item: lutItem(entries: 2, first: 0, bits: 16,
                                          data: wordData([100, 200]))),
        ])
        let lut = try #require(dataSet.modalityLUT())
        #expect(lut.value(for: 1) == 200)
        #expect(dataSet.voiLUT() == nil)
    }

    @Test("A VOI LUT after a negative rescale intercept reads its origin as signed")
    func testVOILUTSignedAfterRescale() throws {
        // PS3.3 C.11.2.1.1: the second Value is SS when the output of the Rescale
        // Slope and Intercept may be signed (always so for CT Hounsfield Units).
        let dataSet = DataSet(elements: [
            decimalElement(DICOMCore.Tag(group: 0x0028, element: 0x1052), "-1024"),
            decimalElement(DICOMCore.Tag(group: 0x0028, element: 0x1053), "1"),
            sequenceElement(DICOMCore.Tag(group: 0x0028, element: 0x3010),
                            item: lutItem(entries: 2, first: 0xFC00, bits: 16,
                                          data: wordData([0, 4095]))),
        ])
        let lut = try #require(dataSet.voiLUT())
        #expect(lut.firstMappedValue == -1024,
                "the VOI input is rescaled output, which starts at the intercept")
    }
}
