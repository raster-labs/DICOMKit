//
// SegmentationPaletteColorTests.swift
// DICOMKit
//
// PALETTE COLOR LABELMAP output (D37 b), pinned to PS3.3 2026a:
// - Table C.8.20-2: Photometric Interpretation MONOCHROME2 for BINARY/FRACTIONAL,
//   MONOCHROME2 or PALETTE COLOR for LABELMAP; Recommended Display CIELab Value "shall not
//   be present" for a PALETTE COLOR LABELMAP
// - Table A.51-1: Palette Color Lookup Table (C.7.9) and ICC Profile (C.11.15) Modules
//   "Required if Photometric Interpretation (0028,0004) has a Value of PALETTE COLOR";
//   A.1.3.2: otherwise "no information defined in that Module shall be present"
// - Table C.7-22a / C.7.6.3.1.5: descriptors (0028,1101-1103) VM 3, 8 or 16 bits per
//   entry in the Segmentation IOD; Data (0028,1201-1203) required, segmented data
//   (0028,1221-1223) "shall not be present in a ... Segmentation IOD"
// - C.7.6.3.1.6: 8-bit intensities replicated into both bytes of a 16-bit entry
// - C.11.15.1.1: ICC profile class "scnr", colour space "RGB ", PCS "Lab " or "XYZ "
// Tags and VRs: PS3.6 2026a Table 6-1.
//

import XCTest
@testable import DICOMKit
import DICOMCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class SegmentationPaletteColorTests: XCTestCase {

    /// CID 7150 "Anatomical Structure" and CID 7154 (in CID 7151 via CID 7192) "Liver"
    private let anatomicalStructure = CodedConcept(codeValue: "91723000", codingSchemeDesignator: "SCT", codeMeaning: "Anatomical Structure")
    private let liver = CodedConcept(codeValue: "10200004", codingSchemeDesignator: "SCT", codeMeaning: "Liver")

    private func paletteBuilder() throws -> SegmentationBuilder {
        try SegmentationBuilder(rows: 1, columns: 4, segmentationType: .labelmap,
                                studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addLabelmapSegment(number: 0, label: "Background",
                                category: anatomicalStructure, type: liver)
            .addLabelmapSegment(number: 1, label: "Liver",
                                category: anatomicalStructure, type: liver,
                                color: (r: 139, g: 69, b: 19))
            .addLabelmapSegment(number: 3, label: "Other",
                                category: anatomicalStructure, type: liver,
                                color: (r: 255, g: 0, b: 128))
            .setPixelPaddingValue(0)
            .addLabelmapFrame([0, 1, 3, 1])
            .setPaletteColor()
    }

    // MARK: - Builder

    func test_setPaletteColor_buildsPaletteColorLabelmap() throws {
        let (segmentation, _) = try paletteBuilder().build()
        XCTAssertEqual(segmentation.photometricInterpretation, "PALETTE COLOR")
        XCTAssertEqual(segmentation.sopClassUID, Segmentation.labelMapSegmentationStorageUID)

        let lut = try XCTUnwrap(segmentation.paletteColorLookupTable)
        // One entry per value 0...largest Segment Number, first value mapped 0, 16 bits
        XCTAssertEqual(lut.redDescriptor, PaletteColorLUT.Descriptor(numberOfEntries: 4, firstMappedValue: 0, bitsPerEntry: 16))
        XCTAssertEqual(lut.greenDescriptor, lut.redDescriptor)
        XCTAssertEqual(lut.blueDescriptor, lut.redDescriptor)
        // C.7.6.3.1.6: 8-bit value v becomes v * 0x101; undescribed value 2 and colourless 0 are black
        XCTAssertEqual(lut.redLUT, [0, 139 * 0x101, 0, 0xFFFF])
        XCTAssertEqual(lut.greenLUT, [0, 69 * 0x101, 0, 0])
        XCTAssertEqual(lut.blueLUT, [0, 19 * 0x101, 0, 128 * 0x101])

        // C.8.20-2: no Recommended Display CIELab Value with PALETTE COLOR
        XCTAssertTrue(segmentation.segments.allSatisfy { $0.recommendedDisplayCIELabValue == nil })

        // Default ICC profile: the fixed sRGB Input Device profile, Color Space SRGB
        XCTAssertEqual(segmentation.iccProfile, SRGBICCProfileWriter.profileData)
        XCTAssertEqual(segmentation.colorSpace, "SRGB")
    }

    func test_setPaletteColor_rejectedForBinary() throws {
        let builder = SegmentationBuilder(rows: 1, columns: 1, segmentationType: .binary,
                                          studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
        try builder.addBinarySegment(number: 1, label: "A", mask: [1],
                                     category: anatomicalStructure, type: liver)
        builder.setPaletteColor()
        XCTAssertThrowsError(try builder.build()) { error in
            guard case SegmentationBuilderError.invalidSegmentationType(expected: .labelmap, got: .binary) = error else {
                return XCTFail("expected invalidSegmentationType, got \(error)")
            }
        }
    }

    func test_monochrome2Labelmap_hasNoPaletteOrICCProfile() throws {
        let (segmentation, pixelData) = try SegmentationBuilder(
            rows: 1, columns: 2, segmentationType: .labelmap,
            studyInstanceUID: "1.2.3", seriesInstanceUID: "1.2.3.4")
            .addLabelmapSegment(number: 0, label: "Background", category: anatomicalStructure, type: liver)
            .addLabelmapSegment(number: 1, label: "Liver", category: anatomicalStructure, type: liver,
                                color: (r: 1, g: 2, b: 3))
            .addLabelmapFrame([0, 1])
            .build()
        XCTAssertEqual(segmentation.photometricInterpretation, "MONOCHROME2")
        XCTAssertNil(segmentation.paletteColorLookupTable)
        XCTAssertNil(segmentation.iccProfile)
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)
        // A.1.3.2: neither Conditional Module is present for MONOCHROME2
        for tag: Tag in [.redPaletteColorLookupTableDescriptor, .redPaletteColorLookupTableData,
                         .iccProfile, .colorSpace] {
            XCTAssertNil(dataSet[tag], "\(tag) must not be present for MONOCHROME2")
        }
        XCTAssertNotNil(dataSet.sequence(for: .segmentSequence)?[1][.recommendedDisplayCIELabValue])
    }

    // MARK: - DataSet

    func test_buildDataSet_writesPaletteAndICCProfileModules() throws {
        let (segmentation, pixelData) = try paletteBuilder().build()
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)

        XCTAssertEqual(dataSet.string(for: .photometricInterpretation), "PALETTE COLOR")
        XCTAssertEqual(dataSet.string(for: .segmentationType), "LABELMAP")
        XCTAssertEqual(dataSet.uint16(for: .samplesPerPixel), 1)
        XCTAssertEqual(dataSet.uint16(for: .pixelRepresentation), 0)

        // Table C.7-22a descriptors: US (Pixel Representation 0), VM 3
        for tag: Tag in [.redPaletteColorLookupTableDescriptor, .greenPaletteColorLookupTableDescriptor,
                         .bluePaletteColorLookupTableDescriptor] {
            XCTAssertEqual(dataSet[tag]?.vr, .US)
            XCTAssertEqual(dataSet[tag]?.uint16Values, [4, 0, 16])
        }
        // Table C.7-22a data: OW, one little-endian word per 16-bit entry
        XCTAssertEqual(dataSet[.redPaletteColorLookupTableData]?.vr, .OW)
        XCTAssertEqual(dataSet[.redPaletteColorLookupTableData]?.valueData,
                       Data([0x00, 0x00, 0x8B, 0x8B, 0x00, 0x00, 0xFF, 0xFF]))
        XCTAssertEqual(dataSet[.bluePaletteColorLookupTableData]?.valueData,
                       Data([0x00, 0x00, 0x13, 0x13, 0x00, 0x00, 0x80, 0x80]))
        // Segmented palette data shall not be present in a Segmentation IOD
        for tag: Tag in [.segmentedRedPaletteColorLookupTableData, .segmentedGreenPaletteColorLookupTableData,
                         .segmentedBluePaletteColorLookupTableData] {
            XCTAssertNil(dataSet[tag])
        }

        // ICC Profile Module (Table C.11.15-1): ICC Profile OB Type 1, Color Space CS
        XCTAssertEqual(dataSet[.iccProfile]?.vr, .OB)
        XCTAssertEqual(dataSet[.iccProfile]?.valueData, SRGBICCProfileWriter.profileData)
        XCTAssertEqual(dataSet.string(for: .colorSpace), "SRGB")

        // Table C.8.20-2: no Recommended Display CIELab Value
        let segments = try XCTUnwrap(dataSet.sequence(for: .segmentSequence))
        XCTAssertTrue(segments.allSatisfy { $0[.recommendedDisplayCIELabValue] == nil })
    }

    func test_paletteColorLabelmap_roundTripsThroughParser() throws {
        let (segmentation, pixelData) = try paletteBuilder().build()
        let dataSet = try segmentation.buildDataSet(pixelData: pixelData)
        let parsed = try SegmentationParser.parse(from: dataSet)

        XCTAssertEqual(parsed.photometricInterpretation, "PALETTE COLOR")
        XCTAssertEqual(parsed.paletteColorLookupTable, segmentation.paletteColorLookupTable)
        XCTAssertEqual(parsed.iccProfile, SRGBICCProfileWriter.profileData)
        XCTAssertEqual(parsed.colorSpace, "SRGB")
        // The palette entry at a Segment Number is that segment's colour
        let color = try XCTUnwrap(parsed.paletteColorLookupTable).lookup(1)
        XCTAssertEqual([color.red, color.green, color.blue], [139, 69, 19])
        // And the pixel values are still the Segment Numbers
        XCTAssertEqual(SegmentationPixelDataExtractor.extractLabelmapFrame(
            from: pixelData, frameIndex: 0, rows: 1, columns: 4, bitsAllocated: 8), [0, 1, 3, 1])
    }

    func test_eightBitPaletteEntries_writtenOneBytePerEntry() throws {
        // C.7.6.3.1.5: the Segmentation IOD allows 8 bits per entry, stored "equivalent to
        // 8 bits allocated"; an odd count is padded to even length.
        let descriptor = PaletteColorLUT.Descriptor(numberOfEntries: 3, firstMappedValue: 0, bitsPerEntry: 8)
        let lut = PaletteColorLUT(redDescriptor: descriptor, greenDescriptor: descriptor, blueDescriptor: descriptor,
                                  redLUT: [0, 0x1100, 0xFF00], greenLUT: [0, 0, 0], blueLUT: [0, 0, 0])
        let dataSet = try segmentation(lut: lut).buildDataSet(pixelData: Data([0, 1]))
        XCTAssertEqual(dataSet[.redPaletteColorLookupTableDescriptor]?.uint16Values, [3, 0, 8])
        XCTAssertEqual(dataSet[.redPaletteColorLookupTableData]?.valueData, Data([0x00, 0x11, 0xFF, 0x00]))
    }

    // MARK: - buildDataSet validation

    private func segmentation(
        type: SegmentationType = .labelmap,
        photometric: String = "PALETTE COLOR",
        lut: PaletteColorLUT? = PaletteColorLUT(
            redDescriptor: .init(numberOfEntries: 2, firstMappedValue: 0, bitsPerEntry: 16),
            greenDescriptor: .init(numberOfEntries: 2, firstMappedValue: 0, bitsPerEntry: 16),
            blueDescriptor: .init(numberOfEntries: 2, firstMappedValue: 0, bitsPerEntry: 16),
            redLUT: [0, 1], greenLUT: [0, 1], blueLUT: [0, 1]),
        iccProfile: Data? = SRGBICCProfileWriter.profileData,
        cieLab: CIELabColor? = nil
    ) -> Segmentation {
        Segmentation(
            sopInstanceUID: "1.2.3.9", seriesInstanceUID: "1.2.3.4", studyInstanceUID: "1.2.3",
            segmentationType: type,
            numberOfSegments: 2,
            segments: [
                Segment(segmentNumber: 0, segmentLabel: "Background", category: anatomicalStructure, type: liver),
                Segment(segmentNumber: 1, segmentLabel: "Liver", category: anatomicalStructure, type: liver,
                        recommendedDisplayCIELabValue: cieLab),
            ],
            numberOfFrames: 1, rows: 1, columns: 2,
            bitsAllocated: type == .binary ? 1 : 8, bitsStored: type == .binary ? 1 : 8, highBit: type == .binary ? 0 : 7,
            photometricInterpretation: photometric,
            paletteColorLookupTable: lut, iccProfile: iccProfile,
            colorSpace: iccProfile == nil ? nil : "SRGB")
    }

    private func assertThrows(_ segmentation: Segmentation, _ expected: SegmentationDataSetError,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try segmentation.buildDataSet(pixelData: Data([0, 1])), file: file, line: line) { error in
            XCTAssertEqual(error as? SegmentationDataSetError, expected, file: file, line: line)
        }
    }

    func test_buildDataSet_acceptsValidPaletteColorLabelmap() {
        XCTAssertNoThrow(try segmentation().buildDataSet(pixelData: Data([0, 1])))
    }

    func test_buildDataSet_rejectsPaletteColorForBinary() {
        assertThrows(segmentation(type: .binary),
                     .photometricInterpretationNotAllowed("PALETTE COLOR", segmentationType: .binary))
    }

    func test_buildDataSet_rejectsUnknownPhotometricInterpretation() {
        assertThrows(segmentation(photometric: "RGB", lut: nil, iccProfile: nil),
                     .photometricInterpretationNotAllowed("RGB", segmentationType: .labelmap))
    }

    func test_buildDataSet_requiresPaletteAndICCProfileModules() {
        assertThrows(segmentation(lut: nil), .missingModule("Palette Color Lookup Table"))
        assertThrows(segmentation(iccProfile: nil), .missingModule("ICC Profile"))
    }

    func test_buildDataSet_rejectsModulesWithMonochrome2() {
        assertThrows(segmentation(photometric: "MONOCHROME2", iccProfile: nil), .moduleNotAllowed("Palette Color Lookup Table"))
        assertThrows(segmentation(photometric: "MONOCHROME2", lut: nil), .moduleNotAllowed("ICC Profile"))
    }

    func test_buildDataSet_rejectsCIELabWithPaletteColor() {
        assertThrows(segmentation(cieLab: CIELabColor(l: 1, a: 2, b: 3)),
                     .recommendedDisplayCIELabValueNotAllowed(segmentNumber: 1))
    }

    func test_buildDataSet_checksPaletteDescriptors() throws {
        let sixteen = PaletteColorLUT.Descriptor(numberOfEntries: 2, firstMappedValue: 0, bitsPerEntry: 16)
        let mismatched = PaletteColorLUT(
            redDescriptor: sixteen, greenDescriptor: .init(numberOfEntries: 2, firstMappedValue: 1, bitsPerEntry: 16),
            blueDescriptor: sixteen, redLUT: [0, 1], greenLUT: [0, 1], blueLUT: [0, 1])
        let twelve = PaletteColorLUT.Descriptor(numberOfEntries: 2, firstMappedValue: 0, bitsPerEntry: 12)
        let twelveBits = PaletteColorLUT(redDescriptor: twelve, greenDescriptor: twelve, blueDescriptor: twelve,
                                         redLUT: [0, 1], greenLUT: [0, 1], blueLUT: [0, 1])
        let short = PaletteColorLUT(redDescriptor: sixteen, greenDescriptor: sixteen, blueDescriptor: sixteen,
                                    redLUT: [0], greenLUT: [0, 1], blueLUT: [0, 1])
        for lut in [mismatched, twelveBits, short] {
            XCTAssertThrowsError(try segmentation(lut: lut).buildDataSet(pixelData: Data([0, 1]))) { error in
                guard case SegmentationDataSetError.invalidPaletteColorLookupTable = error else {
                    return XCTFail("expected invalidPaletteColorLookupTable, got \(error)")
                }
            }
        }
    }

    func test_buildDataSet_checksICCProfileHeader() throws {
        // The default profile meets C.11.15.1.1
        let header = SRGBICCProfileWriter.profileData
        XCTAssertEqual(String(decoding: header[12..<16], as: UTF8.self), "scnr")
        XCTAssertEqual(String(decoding: header[16..<20], as: UTF8.self), "RGB ")
        XCTAssertTrue(["Lab ", "XYZ "].contains(String(decoding: header[20..<24], as: UTF8.self)))

        func replacing(_ offset: Int, with signature: String) -> Data {
            var data = header
            data.replaceSubrange(offset..<offset + 4, with: Data(signature.utf8))
            return data
        }
        for profile in [Data(count: 64), replacing(12, with: "mntr"), replacing(16, with: "GRAY"), replacing(20, with: "RGB ")] {
            XCTAssertThrowsError(try segmentation(iccProfile: profile).buildDataSet(pixelData: Data([0, 1]))) { error in
                guard case SegmentationDataSetError.invalidICCProfile = error else {
                    return XCTFail("expected invalidICCProfile, got \(error)")
                }
            }
        }
    }

    // MARK: - Rendering

    #if canImport(CoreGraphics)
    func test_renderer_usesPaletteColoursForPaletteColorLabelmap() throws {
        let (segmentation, pixelData) = try paletteBuilder().build()
        let parsed = try SegmentationParser.parse(from: try segmentation.buildDataSet(pixelData: pixelData))
        let image = try XCTUnwrap(SegmentationRenderer.renderLabelmap(
            segmentation: parsed, pixelData: pixelData,
            options: SegmentationRenderer.RenderOptions(opacity: 1.0)))
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        func rgba(_ x: Int) -> [UInt8] { Array(bytes[x * 4 ..< x * 4 + 4]) }
        XCTAssertEqual(rgba(0)[3], 0, "Pixel Padding Value (background) stays transparent")
        XCTAssertEqual(rgba(1), [139, 69, 19, 255], "Segment 1 in its palette colour")
        XCTAssertEqual(rgba(2), [255, 0, 128, 255], "Segment 3 in its palette colour")
    }
    #endif
}
