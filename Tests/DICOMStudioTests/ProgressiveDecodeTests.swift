// ProgressiveDecodeTests.swift
// DICOMStudio
//
// Phase 8 — Progressive JPEG 2000 decode tests

import Foundation
import Testing
@testable import DICOMStudio
@testable import DICOMCore
@testable import DICOMKit

// MARK: - ProgressiveDecodeLevelTests

@Suite("ProgressiveDecodeLevel")
struct ProgressiveDecodeLevelTests {

    @Test("allCases has three levels")
    func testAllCasesCount() {
        #expect(ProgressiveDecodeLevel.allCases.count == 3)
    }

    @Test("quarter scaleFactor is 0.25")
    func testQuarterScale() {
        #expect(ProgressiveDecodeLevel.quarter.scaleFactor == 0.25)
    }

    @Test("half scaleFactor is 0.5")
    func testHalfScale() {
        #expect(ProgressiveDecodeLevel.half.scaleFactor == 0.5)
    }

    @Test("full scaleFactor is 1.0")
    func testFullScale() {
        #expect(ProgressiveDecodeLevel.full.scaleFactor == 1.0)
    }

    @Test("quarter shortLabel is 25%")
    func testQuarterLabel() {
        #expect(ProgressiveDecodeLevel.quarter.shortLabel == "25%")
    }

    @Test("half shortLabel is 50%")
    func testHalfLabel() {
        #expect(ProgressiveDecodeLevel.half.shortLabel == "50%")
    }

    @Test("full shortLabel is 100%")
    func testFullLabel() {
        #expect(ProgressiveDecodeLevel.full.shortLabel == "100%")
    }

    @Test("only full isFinal")
    func testIsFinal() {
        #expect(ProgressiveDecodeLevel.full.isFinal == true)
        #expect(ProgressiveDecodeLevel.quarter.isFinal == false)
        #expect(ProgressiveDecodeLevel.half.isFinal == false)
    }

    @Test("rawValue order is ascending")
    func testRawValueOrder() {
        #expect(ProgressiveDecodeLevel.quarter.rawValue < ProgressiveDecodeLevel.half.rawValue)
        #expect(ProgressiveDecodeLevel.half.rawValue   < ProgressiveDecodeLevel.full.rawValue)
    }
}

// MARK: - ProgressiveDecodeStateTests

@Suite("ProgressiveDecodeState")
struct ProgressiveDecodeStateTests {

    @Test("idle equals idle")
    func testIdleEquality() {
        #expect(ProgressiveDecodeState.idle == ProgressiveDecodeState.idle)
    }

    @Test("unavailable equals unavailable")
    func testUnavailableEquality() {
        #expect(ProgressiveDecodeState.unavailable == ProgressiveDecodeState.unavailable)
    }

    @Test("decoding(level:) equality matches level")
    func testDecodingEquality() {
        #expect(
            ProgressiveDecodeState.decoding(level: .quarter) ==
            ProgressiveDecodeState.decoding(level: .quarter)
        )
        #expect(
            ProgressiveDecodeState.decoding(level: .quarter) !=
            ProgressiveDecodeState.decoding(level: .half)
        )
    }

    @Test("complete(totalDecodeMs:) equality matches value")
    func testCompleteEquality() {
        #expect(
            ProgressiveDecodeState.complete(totalDecodeMs: 42.0) ==
            ProgressiveDecodeState.complete(totalDecodeMs: 42.0)
        )
        #expect(
            ProgressiveDecodeState.complete(totalDecodeMs: 1.0) !=
            ProgressiveDecodeState.complete(totalDecodeMs: 2.0)
        )
    }
}

// MARK: - ProgressiveDecodeHelpersTests

@Suite("ProgressiveDecodeHelpers")
struct ProgressiveDecodeHelpersTests {

    // MARK: accessibilityLabel

    @Test("accessibilityLabel idle nonEmpty")
    func testA11yLabelIdle() {
        #expect(ProgressiveDecodeHelpers.accessibilityLabel(for: .idle).isEmpty == false)
    }

    @Test("accessibilityLabel unavailable nonEmpty")
    func testA11yLabelUnavailable() {
        #expect(ProgressiveDecodeHelpers.accessibilityLabel(for: .unavailable).isEmpty == false)
    }

    @Test("accessibilityLabel decoding contains percent")
    func testA11yLabelDecoding() {
        let label = ProgressiveDecodeHelpers.accessibilityLabel(for: .decoding(level: .half))
        #expect(label.contains("50%"))
    }

    @Test("accessibilityLabel complete contains ms")
    func testA11yLabelComplete() {
        let label = ProgressiveDecodeHelpers.accessibilityLabel(for: .complete(totalDecodeMs: 123))
        #expect(label.contains("123"))
    }

    // MARK: badgeText

    @Test("badgeText idle returns nil")
    func testBadgeTextIdle() {
        #expect(ProgressiveDecodeHelpers.badgeText(for: .idle) == nil)
    }

    @Test("badgeText unavailable returns nil")
    func testBadgeTextUnavailable() {
        #expect(ProgressiveDecodeHelpers.badgeText(for: .unavailable) == nil)
    }

    @Test("badgeText complete returns nil")
    func testBadgeTextComplete() {
        #expect(ProgressiveDecodeHelpers.badgeText(for: .complete(totalDecodeMs: 10)) == nil)
    }

    @Test("badgeText decoding quarter is non-nil and contains 25%")
    func testBadgeTextDecodingQuarter() {
        let badge = ProgressiveDecodeHelpers.badgeText(for: .decoding(level: .quarter))
        #expect(badge != nil)
        #expect(badge?.contains("25%") == true)
    }

    @Test("badgeText decoding half is non-nil and contains 50%")
    func testBadgeTextDecodingHalf() {
        let badge = ProgressiveDecodeHelpers.badgeText(for: .decoding(level: .half))
        #expect(badge != nil)
        #expect(badge?.contains("50%") == true)
    }

    // MARK: isProgressSpinnerVisible

    @Test("isProgressSpinnerVisible true only for decoding")
    func testSpinnerVisible() {
        #expect(ProgressiveDecodeHelpers.isProgressSpinnerVisible(for: .decoding(level: .quarter)) == true)
        #expect(ProgressiveDecodeHelpers.isProgressSpinnerVisible(for: .idle) == false)
        #expect(ProgressiveDecodeHelpers.isProgressSpinnerVisible(for: .unavailable) == false)
        #expect(ProgressiveDecodeHelpers.isProgressSpinnerVisible(for: .complete(totalDecodeMs: 0)) == false)
    }

    // MARK: isJ2KTransferSyntax

    @Test("isJ2KTransferSyntax J2K lossless UID true")
    func testIsJ2KLossless() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.90") == true)
    }

    @Test("isJ2KTransferSyntax J2K lossy UID true")
    func testIsJ2KLossy() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.91") == true)
    }

    @Test("isJ2KTransferSyntax HTJ2K lossless UID true")
    func testIsHTJ2KLossless() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.201") == true)
    }

    @Test("isJ2KTransferSyntax HTJ2K RPCL UID true")
    func testIsHTJ2KRPCL() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.202") == true)
    }

    @Test("isJ2KTransferSyntax HTJ2K lossy UID true")
    func testIsHTJ2KLossy() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.203") == true)
    }

    @Test("isJ2KTransferSyntax Part2 lossless UID true")
    func testIsJ2KPart2Lossless() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.92") == true)
    }

    @Test("isJ2KTransferSyntax Part2 lossy UID true")
    func testIsJ2KPart2Lossy() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.93") == true)
    }

    @Test("isJ2KTransferSyntax uncompressed UID false")
    func testIsJ2KUncompressed() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.1") == false)
    }

    @Test("isJ2KTransferSyntax JPEG baseline UID false")
    func testIsJ2KJPEGBaseline() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("1.2.840.10008.1.2.4.50") == false)
    }

    @Test("isJ2KTransferSyntax unknown UID false")
    func testIsJ2KUnknown() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("9.9.9.9") == false)
    }

    @Test("isJ2KTransferSyntax empty string false")
    func testIsJ2KEmpty() {
        #expect(ProgressiveDecodeHelpers.isJ2KTransferSyntax("") == false)
    }
}

// MARK: - ImageDecodingService progressive tests

@Suite("ImageDecodingService progressive")
struct ImageDecodingServiceProgressiveTests {

    @Test("decodeProgressively non-J2K file yields nothing")
    func testNonJ2KYieldsNothing() async throws {
        let svc = ImageDecodingService()
        let data = try makeMinimalUncompressedDICOM()
        let file = try DICOMFile.read(from: data)
        #if canImport(CoreGraphics)
        let stream = svc.decodeProgressively(file: file)
        var count = 0
        for await _ in stream { count += 1 }
        #expect(count == 0)
        #endif
    }

    @Test("decodeProgressively J2K 64x64 file streams real quarter, half, and full wavelet levels")
    func testJ2KStreamsQuarterHalfFull() async throws {
        #if canImport(CoreGraphics)
        var ds = DataSet()
        ds.setUInt16(64, for: .rows)
        ds.setUInt16(64, for: .columns)
        ds.setUInt16(8, for: .bitsAllocated)
        ds.setUInt16(8, for: .bitsStored)
        ds.setUInt16(7, for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        var raw = Data(capacity: 64 * 64)
        for y in 0..<64 {
            for x in 0..<64 {
                raw.append(UInt8((x * 4 + y * 2) & 0xFF))
            }
        }
        ds[.pixelData] = DataElement.data(tag: .pixelData, vr: .OB, data: raw)
        let uncompressed = try DICOMFile.create(
            dataSet: ds,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.7",
            sopInstanceUID: "1.2.3.4.5.64",
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        ).write()
        let j2kData = try CompressionManager().compressData(
            uncompressed, codec: "htj2k-lossless", quality: nil
        )
        let j2kFile = try DICOMFile.read(from: j2kData)

        var stages: [(ProgressiveDecodeLevel, Int, Int)] = []
        for await (level, image, _) in ImageDecodingService().decodeProgressively(file: j2kFile) {
            stages.append((level, image.width, image.height))
        }

        #expect(stages.map(\.0) == [.quarter, .half, .full])
        #expect(stages[0].1 == 16 && stages[0].2 == 16)
        #expect(stages[1].1 == 32 && stages[1].2 == 32)
        #expect(stages[2].1 == 64 && stages[2].2 == 64)
        #endif
    }

    // MARK: - Helpers

    private func makeMinimalUncompressedDICOM() throws -> Data {
        var d = Data()
        d.append(contentsOf: [UInt8](repeating: 0, count: 128))
        d.append(contentsOf: [0x44, 0x49, 0x43, 0x4D]) // DICM preamble

        func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
        func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF),
             UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)]
        }
        func tag(_ g: UInt16, _ e: UInt16, _ vr: String, _ v: [UInt8]) -> Data {
            var x = Data()
            x += le16(g); x += le16(e)
            x += [UInt8](vr.utf8)
            x += le16(UInt16(v.count))
            x += v; return x
        }
        func uid(_ s: String) -> [UInt8] { Array(s.utf8) }

        var meta = Data()
        meta += tag(0x0002, 0x0001, "OB", [0x00, 0x01])
        meta += tag(0x0002, 0x0002, "UI", uid("1.2.840.10008.5.1.4.1.1.2"))
        meta += tag(0x0002, 0x0003, "UI", uid("1.2.3.4.5"))
        meta += tag(0x0002, 0x0010, "UI", uid("1.2.840.10008.1.2.1")) // Explicit VR LE

        let ml = UInt32(meta.count)
        d += tag(0x0002, 0x0000, "UL", le32(ml))
        d += meta
        d += tag(0x0008, 0x0016, "UI", uid("1.2.840.10008.5.1.4.1.1.2"))
        d += tag(0x0008, 0x0018, "UI", uid("1.2.3.4.5"))
        return d
    }
}

// MARK: - ProgressiveDecodeViewModel tests

@Suite("ImageViewerViewModel progressive")
@MainActor
struct ImageViewerViewModelProgressiveTests {

    @Test("initial progressiveDecodeState is idle")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testInitialState() {
        let vm = ImageViewerViewModel()
        #expect(vm.progressiveDecodeState == .idle)
    }

    @Test("startProgressiveDecode without file leaves state idle")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testStartWithoutFile() {
        let vm = ImageViewerViewModel()
        vm.startProgressiveDecode()
        // Without a loaded file the state should not change from idle.
        #expect(vm.progressiveDecodeState == .idle)
    }

    #if canImport(CoreGraphics)
    @Test("progressiveImage initially nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testProgressiveImageNil() {
        let vm = ImageViewerViewModel()
        #expect(vm.progressiveImage == nil)
    }
    #endif
}
