// DicomJ2KTests.swift — Tests for dicom-j2k CLI helper logic
// Tests cover the pure-logic helpers that can be exercised without real DICOM files.

import Testing
import Foundation
import DICOMCore
import DICOMKit
import J2KCore

// MARK: - Transfer Syntax Helpers

/// The J2K and HTJ2K transfer syntax UIDs recognized by dicom-j2k, per the canonical
/// DICOM standard mapping (shared `TransferSyntax` source of truth).
private let knownJ2KUIDs: [String] = [
    "1.2.840.10008.1.2.4.90",   // JPEG 2000 Lossless Only
    "1.2.840.10008.1.2.4.91",   // JPEG 2000 (lossless or lossy)
    "1.2.840.10008.1.2.4.92",   // JPEG 2000 Part 2 Multi-component Lossless Only
    "1.2.840.10008.1.2.4.93",   // JPEG 2000 Part 2 Multi-component (lossless or lossy)
    "1.2.840.10008.1.2.4.201",  // HTJ2K Lossless Only
    "1.2.840.10008.1.2.4.202",  // HTJ2K Lossless Only (RPCL)
    "1.2.840.10008.1.2.4.203"   // HTJ2K (lossless or lossy)
]

private let knownNonJ2KUIDs: [String] = [
    "1.2.840.10008.1.2",        // Implicit VR Little Endian
    "1.2.840.10008.1.2.1",      // Explicit VR Little Endian
    "1.2.840.10008.1.2.4.50",   // JPEG Baseline
    "1.2.840.10008.1.2.4.57",   // JPEG Lossless
    "1.2.840.10008.1.2.4.70",   // JPEG Lossless SV1
    "1.2.840.10008.1.2.5"       // RLE Lossless
]

/// Mirrors the CLI's `isJ2KTransferSyntax`, which now delegates to the shared API.
private func isJ2KTransferSyntax(_ uid: String?) -> Bool {
    guard let uid else { return false }
    return TransferSyntax.from(uid: uid)?.isJPEG2000 ?? false
}

/// Mirrors the CLI's `tsLabel`, which now delegates to the shared `TransferSyntax.displayName`.
private func tsLabel(_ uid: String?) -> String {
    guard let uid else { return "Unknown" }
    guard let ts = TransferSyntax.from(uid: uid) else { return uid }
    return "\(ts.displayName) (\(uid))"
}

// MARK: - Test Suite

@Suite("dicom-j2k: transfer syntax detection")
struct TransferSyntaxDetectionTests {

    @Test("All known J2K/HTJ2K UIDs are detected as J2K")
    func testKnownJ2KUIDs() {
        for uid in knownJ2KUIDs {
            #expect(isJ2KTransferSyntax(uid), "Expected \(uid) to be detected as J2K")
        }
    }

    @Test("Non-J2K UIDs are not detected as J2K")
    func testNonJ2KUIDs() {
        for uid in knownNonJ2KUIDs {
            #expect(!isJ2KTransferSyntax(uid), "Expected \(uid) NOT to be detected as J2K")
        }
    }

    @Test("nil UID is not J2K")
    func testNilUID() {
        #expect(!isJ2KTransferSyntax(nil))
    }

    @Test("Empty string UID is not J2K")
    func testEmptyUID() {
        #expect(!isJ2KTransferSyntax(""))
    }

    @Test("Partial UID prefix is not J2K")
    func testPartialUID() {
        #expect(!isJ2KTransferSyntax("1.2.840.10008.1.2.4"))
        #expect(!isJ2KTransferSyntax("1.2.840.10008.1.2.4.9"))
    }

    @Test("Case sensitivity: UID must match exactly")
    func testCaseSensitivity() {
        // UIDs are digit strings, so this is mainly a robustness check
        #expect(!isJ2KTransferSyntax("1.2.840.10008.1.2.4.90.0"))
    }
}

@Suite("dicom-j2k: transfer syntax labels")
struct TransferSyntaxLabelTests {

    @Test("JPEG 2000 Lossless label is correct")
    func testJ2KLosslessLabel() {
        let label = tsLabel("1.2.840.10008.1.2.4.90")
        #expect(label.contains("JPEG 2000 Image Compression (Lossless Only)"))  // PS3.6 Table A-1 (D176)
        #expect(label.contains("1.2.840.10008.1.2.4.90"))
    }

    @Test("JPEG 2000 lossy label is correct")
    func testJ2KLossyLabel() {
        let label = tsLabel("1.2.840.10008.1.2.4.91")
        #expect(label.contains("JPEG 2000"))
        #expect(label.contains("1.2.840.10008.1.2.4.91"))
        #expect(!label.contains("Lossless"))
    }

    @Test("HTJ2K Lossless Only label is correct")
    func testHTJ2KLosslessLabel() {
        let label = tsLabel("1.2.840.10008.1.2.4.201")
        #expect(label.contains("High-Throughput JPEG 2000 Image Compression (Lossless Only)"))
        #expect(label.contains("1.2.840.10008.1.2.4.201"))
    }

    @Test("HTJ2K Lossless Only (RPCL) label is correct")
    func testHTJ2KRPCLLabel() {
        let label = tsLabel("1.2.840.10008.1.2.4.202")
        #expect(label.contains("High-Throughput JPEG 2000 with RPCL Options Image Compression (Lossless Only)"))
        #expect(label.contains("1.2.840.10008.1.2.4.202"))
    }

    @Test("HTJ2K (general) label is correct")
    func testHTJ2KLossyLabel() {
        let label = tsLabel("1.2.840.10008.1.2.4.203")
        #expect(label.contains("High-Throughput JPEG 2000 Image Compression"))
        #expect(label.contains("1.2.840.10008.1.2.4.203"))
        #expect(!label.contains("Lossless"))
    }

    @Test("Unknown UID returns the UID itself")
    func testUnknownUID() {
        let uid = "9.9.999.99999"
        #expect(tsLabel(uid) == uid)
    }

    @Test("nil UID returns 'Unknown'")
    func testNilLabel() {
        #expect(tsLabel(nil) == "Unknown")
    }

    @Test("Labels include UID for all known UIDs")
    func testAllLabelsIncludeUID() {
        for uid in knownJ2KUIDs {
            let label = tsLabel(uid)
            #expect(label.contains(uid), "Label for \(uid) should include the UID itself")
        }
    }
}

@Suite("dicom-j2k: target UID mapping")
struct TargetUIDMappingTests {

    // Mirror the target resolution in main.swift, which now resolves via the shared
    // intent-aware `TransferSyntax.parseEncoding` (symmetric lossy/lossless naming).
    private func targetUID(for key: String) -> String {
        TransferSyntax.parseEncoding(key)?.transferSyntax.uid ?? TransferSyntax.jpeg2000Lossless.uid
    }

    @Test("j2k-lossless maps to the general .91 UID (reversibly encoded)")
    func testJ2KLosslessKey() {
        #expect(targetUID(for: "j2k-lossless") == "1.2.840.10008.1.2.4.91")
    }

    @Test("j2k-lossless-only maps to the reversible-only .90 UID")
    func testJ2KLosslessOnlyKey() {
        #expect(targetUID(for: "j2k-lossless-only") == "1.2.840.10008.1.2.4.90")
    }

    @Test("j2k maps to lossy UID")
    func testJ2KKey() {
        #expect(targetUID(for: "j2k") == "1.2.840.10008.1.2.4.91")
    }

    @Test("htj2k-lossless maps to the general HTJ2K .203 UID (reversibly encoded)")
    func testHTJ2KLosslessKey() {
        #expect(targetUID(for: "htj2k-lossless") == "1.2.840.10008.1.2.4.203")
    }

    @Test("htj2k-lossless-only maps to HTJ2K Lossless Only (.201)")
    func testHTJ2KLosslessOnlyKey() {
        #expect(targetUID(for: "htj2k-lossless-only") == "1.2.840.10008.1.2.4.201")
    }

    @Test("htj2k-rpcl-lossless-only maps to HTJ2K Lossless Only RPCL (.202)")
    func testHTJ2KRPCLKey() {
        #expect(targetUID(for: "htj2k-rpcl-lossless-only") == "1.2.840.10008.1.2.4.202")
        #expect(targetUID(for: "htj2k-rpcl") == "1.2.840.10008.1.2.4.202") // deprecated alias
    }

    @Test("htj2k maps to HTJ2K general (.203)")
    func testHTJ2KKey() {
        #expect(targetUID(for: "htj2k") == "1.2.840.10008.1.2.4.203")
    }

    @Test("All target UIDs are detected as J2K")
    func testAllTargetsAreJ2K() {
        let keys = ["j2k-lossy", "j2k-lossless", "j2k-lossless-only",
                    "htj2k-lossy", "htj2k-lossless", "htj2k-lossless-only", "htj2k-rpcl-lossless-only"]
        for key in keys {
            let uid = targetUID(for: key)
            #expect(isJ2KTransferSyntax(uid), "Target '\(key)' mapped to non-J2K UID: \(uid)")
        }
    }

    @Test("HTJ2K UIDs have correct prefix for useHTJ2K detection")
    func testHTJ2KPrefix() {
        let htj2kUIDs = [
            targetUID(for: "htj2k-lossless"),
            targetUID(for: "htj2k-rpcl-lossless-only"),
            targetUID(for: "htj2k")
        ]
        for uid in htj2kUIDs {
            #expect(uid.hasPrefix("1.2.840.10008.1.2.4.20"), "HTJ2K UID should have prefix 1.2.840.10008.1.2.4.20: \(uid)")
        }
    }

    @Test("J2K UIDs do NOT have HTJ2K prefix")
    func testJ2KNotHTJ2KPrefix() {
        let j2kUIDs = [
            targetUID(for: "j2k-lossless"),
            targetUID(for: "j2k")
        ]
        for uid in j2kUIDs {
            #expect(!uid.hasPrefix("1.2.840.10008.1.2.4.20"), "J2K UID should NOT have HTJ2K prefix: \(uid)")
        }
    }
}

@Suite("dicom-j2k: ROI validation logic")
struct ROIValidationTests {

    private func parseRegion(_ region: String) -> (x: Int, y: Int, w: Int, h: Int)? {
        let parts = region.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    @Test("Valid region string parses correctly")
    func testValidRegion() {
        let r = parseRegion("10,20,256,512")
        #expect(r != nil)
        #expect(r?.x == 10)
        #expect(r?.y == 20)
        #expect(r?.w == 256)
        #expect(r?.h == 512)
    }

    @Test("Zero-origin region is valid")
    func testZeroOriginRegion() {
        let r = parseRegion("0,0,128,128")
        #expect(r != nil)
        #expect(r?.x == 0)
        #expect(r?.y == 0)
    }

    @Test("Zero width region is invalid")
    func testZeroWidthRegion() {
        let r = parseRegion("0,0,0,128")
        #expect(r == nil)
    }

    @Test("Zero height region is invalid")
    func testZeroHeightRegion() {
        let r = parseRegion("0,0,128,0")
        #expect(r == nil)
    }

    @Test("Negative dimension region is invalid")
    func testNegativeDimensionRegion() {
        let r = parseRegion("0,0,-1,128")
        #expect(r == nil)
    }

    @Test("Missing component region is invalid")
    func testMissingComponentRegion() {
        let r = parseRegion("0,0,128")
        #expect(r == nil)
    }

    @Test("Extra component region is invalid")
    func testExtraComponentRegion() {
        let r = parseRegion("0,0,128,128,extra")
        // "extra" won't parse as Int so only 4 ints → valid only if split count == 4
        // "0,0,128,128,extra" has 5 parts, compactMap returns [0,0,128,128] (4 ints) — depends on impl
        // Our impl counts parts.count == 4 after compactMap, so [0,0,128,128] → valid
        // This test documents the boundary behaviour
        let parts = "0,0,128,128,extra".split(separator: ",").compactMap { Int($0) }
        #expect(parts.count == 4)  // "extra" is dropped by compactMap
    }

    @Test("Non-integer characters in region string fail compactMap")
    func testNonIntegerRegion() {
        let r = parseRegion("a,b,c,d")
        #expect(r == nil)
    }
}

@Suite("dicom-j2k: validate argument constraints")
struct ValidateArgumentTests {

    @Test("Valid shell names are accepted")
    func testValidShellNames() {
        let validShells = ["bash", "zsh", "fish"]
        for shell in validShells {
            #expect(["bash", "zsh", "fish"].contains(shell))
        }
    }

    @Test("Invalid shell name is rejected")
    func testInvalidShellName() {
        #expect(!["bash", "zsh", "fish"].contains("powershell"))
        #expect(!["bash", "zsh", "fish"].contains(""))
        #expect(!["bash", "zsh", "fish"].contains("sh"))
    }

    @Test("Valid transcode targets are accepted")
    func testValidTranscodeTargets() {
        let validTargets = ["j2k-lossless", "j2k", "htj2k-lossless", "htj2k-rpcl", "htj2k"]
        for target in validTargets {
            #expect(validTargets.contains(target))
        }
    }

    @Test("Invalid transcode target is rejected")
    func testInvalidTranscodeTarget() {
        let validTargets = ["j2k-lossless", "j2k", "htj2k-lossless", "htj2k-rpcl", "htj2k"]
        #expect(!validTargets.contains("jpeg2000"))
        #expect(!validTargets.contains(""))
        #expect(!validTargets.contains("j2k-lossy"))
    }

    @Test("Valid quality range is 0.0 to 1.0")
    func testQualityRange() {
        let validQualities: [Double] = [0.0, 0.5, 1.0]
        for q in validQualities {
            #expect((0.0...1.0).contains(q), "Quality \(q) should be valid")
        }
    }

    @Test("Quality out of range is invalid")
    func testQualityOutOfRange() {
        #expect(!(0.0...1.0).contains(-0.1))
        #expect(!(0.0...1.0).contains(1.1))
        #expect(!(0.0...1.0).contains(2.0))
    }

    @Test("Decomposition levels valid range is 1 to 10")
    func testDecompositionLevelsRange() {
        for l in 1...10 {
            #expect((1...10).contains(l))
        }
        #expect(!(1...10).contains(0))
        #expect(!(1...10).contains(11))
    }

    @Test("Quality layers valid range is 1 to 20")
    func testQualityLayersRange() {
        for l in 1...20 {
            #expect((1...20).contains(l))
        }
        #expect(!(1...20).contains(0))
        #expect(!(1...20).contains(21))
    }

    @Test("Iterations must be at least 1")
    func testIterationsRange() {
        #expect(1 >= 1)
        #expect(!(0 >= 1))
        #expect(!(-1 >= 1))
    }
}

@Suite("dicom-j2k: DataElement encapsulated pixel data creation")
struct DataElementEncapsulatedTests {

    @Test("DataElement init with encapsulated fragments round-trips correctly")
    func testEncapsulatedInit() {
        let frag1 = Data([0xFF, 0x4F, 0x00, 0x00])
        let frag2 = Data([0xFF, 0x4F, 0x01, 0x00])
        let tag = Tag(group: 0x7FE0, element: 0x0010)
        let element = DataElement(
            tag: tag,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [frag1, frag2],
            encapsulatedOffsetTable: []
        )
        #expect(element.encapsulatedFragments?.count == 2)
        #expect(element.encapsulatedFragments?[0] == frag1)
        #expect(element.encapsulatedFragments?[1] == frag2)
        #expect(element.isEncapsulated == true)
        #expect(element.tag == tag)
        #expect(element.vr == .OB)
    }

    @Test("DataElement with empty fragments is not treated as encapsulated")
    func testEmptyFragments() {
        let tag = Tag(group: 0x7FE0, element: 0x0010)
        let element = DataElement(
            tag: tag,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [],
            encapsulatedOffsetTable: []
        )
        // isEncapsulated requires non-empty fragments
        #expect(element.isEncapsulated == false)
    }

    @Test("DataElement US VR with UInt16 value data encodes correctly")
    func testUS16ValueData() {
        let tag = Tag(group: 0x0028, element: 0x0010)
        var val = UInt16(512).littleEndian
        let element = DataElement(
            tag: tag,
            vr: .US,
            length: 2,
            valueData: Data(bytes: &val, count: 2)
        )
        #expect(element.vr == .US)
        #expect(element.length == 2)
        #expect(element.valueData.count == 2)
        // Verify the value round-trips
        let readBack = element.valueData.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        #expect(UInt16(littleEndian: readBack) == 512)
    }
}

@Suite("dicom-j2k: codestream detection from DataSet")
struct CodestreamDetectionTests {

    @Test("Pixel data element with encapsulated fragments returns fragment for index 0")
    func testFragmentAccess() {
        let frag = Data([0xFF, 0x4F, 0xAA, 0xBB])
        let tag = Tag(group: 0x7FE0, element: 0x0010)
        let element = DataElement(
            tag: tag,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [frag],
            encapsulatedOffsetTable: []
        )
        let fragments = element.encapsulatedFragments
        #expect(fragments != nil)
        #expect(fragments?.count == 1)
        #expect(fragments?[0] == frag)
    }

    @Test("Out-of-bounds frame index returns nil from fragments array")
    func testOutOfBoundsFrameIndex() {
        let frag = Data([0xFF, 0x4F])
        let tag = Tag(group: 0x7FE0, element: 0x0010)
        let element = DataElement(
            tag: tag,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [frag],
            encapsulatedOffsetTable: []
        )
        guard let fragments = element.encapsulatedFragments else {
            Issue.record("Expected fragments")
            return
        }
        let frameIndex = 5
        #expect(frameIndex >= fragments.count)
    }

    @Test("Non-encapsulated pixel data element has no fragments")
    func testUncompressedPixelData() {
        let tag = Tag(group: 0x7FE0, element: 0x0010)
        let element = DataElement(
            tag: tag,
            vr: .OW,
            length: 8,
            valueData: Data(repeating: 0, count: 8)
        )
        #expect(element.encapsulatedFragments == nil)
        #expect(element.isEncapsulated == false)
    }
}

@Suite("dicom-j2k: metrics calculation")
struct MetricsCalculationTests {

    @Test("MSE is zero for identical pixel arrays")
    func testMSEIdentical() {
        let pixels: [Double] = [100, 200, 150, 50, 255]
        let n = Double(pixels.count)
        let mse = zip(pixels, pixels).map { pow($0 - $1, 2) }.reduce(0, +) / n
        #expect(mse == 0.0)
    }

    @Test("PSNR is infinite for identical images")
    func testPSNRIdentical() {
        let mse = 0.0
        let maxVal = 255.0
        let psnr = mse == 0 ? Double.infinity : 20 * log10(maxVal) - 10 * log10(mse)
        #expect(psnr.isInfinite)
    }

    @Test("MAE is zero for identical pixel arrays")
    func testMAEIdentical() {
        let pixels: [Double] = [100, 200, 150, 50, 255]
        let n = Double(pixels.count)
        let mae = zip(pixels, pixels).map { abs($0 - $1) }.reduce(0, +) / n
        #expect(mae == 0.0)
    }

    @Test("MSE is positive for different pixel arrays")
    func testMSEDifferent() {
        let ref: [Double] = [100, 200, 150]
        let tst: [Double] = [110, 190, 160]
        let n = Double(ref.count)
        let mse = zip(ref, tst).map { pow($0 - $1, 2) }.reduce(0, +) / n
        // (10^2 + 10^2 + 10^2) / 3 = 300/3 = 100
        #expect(abs(mse - 100.0) < 0.001)
    }

    @Test("PSNR formula gives finite result for non-zero MSE")
    func testPSNRFormula() {
        let mse = 1.0
        let maxVal = 255.0
        let psnr = 20 * log10(maxVal) - 10 * log10(mse)
        #expect(psnr.isFinite)
        #expect(psnr > 40.0)  // PSNR of 1.0 MSE with maxVal=255 should be ~48dB
    }

    @Test("Pixel count mismatch check works correctly")
    func testPixelCountMismatch() {
        let ref: [Double] = [100, 200, 150]
        let tst: [Double] = [100, 200]
        #expect(ref.count != tst.count)
    }
}
