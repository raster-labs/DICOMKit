// CodecInspectorTests.swift -- Phase 8 codec inspector tests
import Foundation
import Testing
@testable import DICOMStudio
@testable import DICOMCore
@testable import DICOMKit

@Suite("CodecInspectorHelpers")
struct CodecInspectorHelpersTests {
    @Test("backendDisplayName metal nonEmpty")
    func testBDN_metal() { #expect(CodecInspectorHelpers.backendDisplayName(.metal).isEmpty == false) }
    @Test("backendDisplayName accelerate nonEmpty")
    func testBDN_accel() { #expect(CodecInspectorHelpers.backendDisplayName(.accelerate).isEmpty == false) }
    @Test("backendDisplayName scalar nonEmpty")
    func testBDN_scalar() { #expect(CodecInspectorHelpers.backendDisplayName(.scalar).isEmpty == false) }
    @Test("backendSFSymbol metal is cpu")
    func testSF_metal() { #expect(CodecInspectorHelpers.backendSFSymbol(.metal) == "cpu") }
    @Test("backendSFSymbol accelerate is bolt.fill")
    func testSF_accel() { #expect(CodecInspectorHelpers.backendSFSymbol(.accelerate) == "bolt.fill") }
    @Test("backendSFSymbol scalar nonEmpty")
    func testSF_scalar() { #expect(CodecInspectorHelpers.backendSFSymbol(.scalar).isEmpty == false) }
    @Test("formatDecodeTime 0 lt 1 ms")
    func testFDT_zero() { #expect(CodecInspectorHelpers.formatDecodeTime(0.0) == "< 1 ms") }
    @Test("formatDecodeTime 42 ms")
    func testFDT_42() { #expect(CodecInspectorHelpers.formatDecodeTime(42.0) == "42 ms") }
    @Test("formatDecodeTime 1500 shows seconds")
    func testFDT_1500() {
        let r = CodecInspectorHelpers.formatDecodeTime(1500.0)
        #expect(r.contains("s") && r.hasSuffix("ms") == false)
    }
    @Test("codecDisplayName J2K nonEmpty")
    func testCDN_j2k() { #expect(CodecInspectorHelpers.codecDisplayName(for: "1.2.840.10008.1.2.4.90").isEmpty == false) }
    @Test("codecDisplayName HTJ2K nonEmpty")
    func testCDN_htj2k() { #expect(CodecInspectorHelpers.codecDisplayName(for: "1.2.840.10008.1.2.4.201").isEmpty == false) }
    @Test("codecDisplayName unknown nonEmpty")
    func testCDN_unk() { #expect(CodecInspectorHelpers.codecDisplayName(for: "9.9.9.9").isEmpty == false) }
    @Test("Every non-retired PS3.6 2026a Table A-1 transfer syntax names its codec")
    func testCDN_everyRegisteredSyntaxNamed() {
        for ts in TransferSyntax.allKnown where !ts.isRetired {
            #expect(!CodecInspectorHelpers.codecDisplayName(for: ts.uid).hasPrefix("Unknown"), "\(ts.uid) \(ts.displayName)")
        }
        #expect(CodecInspectorHelpers.codecDisplayName(for: TransferSyntax.jpegXL.uid) == "JPEG XL")
        #expect(CodecInspectorHelpers.codecDisplayName(for: TransferSyntax.encapsulatedUncompressedExplicitVRLittleEndian.uid) == "Uncompressed")
        #expect(CodecInspectorHelpers.codecDisplayName(for: TransferSyntax.deflatedExplicitVRLittleEndian.uid) == "Uncompressed")
        #expect(CodecInspectorHelpers.codecDisplayName(for: TransferSyntax.deflatedImageFrameCompression.uid).hasPrefix("Deflate"))
        #expect(CodecInspectorHelpers.codecDisplayName(for: "1.2.840.10008.1.2.4.102").hasPrefix("Video"))
    }
    @Test("statusSummary noImage nonEmpty")
    func testSS_noImage() { #expect(CodecInspectorHelpers.statusSummary(.noImage).isEmpty == false) }
    @Test("statusSummary decoding nonEmpty")
    func testSS_decoding() { #expect(CodecInspectorHelpers.statusSummary(.decoding).isEmpty == false) }
    @Test("statusSummary uncompressed nonEmpty")
    func testSS_uncompressed() {
        #expect(CodecInspectorHelpers.statusSummary(.uncompressed(transferSyntaxDescription: "ELE")).isEmpty == false)
    }
    @Test("statusSummary unsupported contains UID")
    func testSS_unsupported() {
        #expect(CodecInspectorHelpers.statusSummary(.unsupportedCodec(transferSyntaxUID: "1.2.3.4")).contains("1.2.3.4"))
    }
}

@Suite("CodecInspectorViewModel")
struct CodecInspectorViewModelTests {
    @Test("initial status noImage")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testInitStatus() {
        let vm = CodecInspectorViewModel()
        guard case .noImage = vm.status else { Issue.record("Expected .noImage"); return }
    }
    @Test("hasEntry initially false")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testHasEntryFalse() { #expect(CodecInspectorViewModel().hasEntry == false) }
    @Test("entry initially nil")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testEntryNil() { #expect(CodecInspectorViewModel().entry == nil) }
    @Test("isVisible default false")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testIsVisible() { #expect(CodecInspectorViewModel().isVisible == false) }
    @Test("markDecoding sets decoding")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testMarkDecoding() {
        let vm = CodecInspectorViewModel(); vm.markDecoding()
        guard case .decoding = vm.status else { Issue.record("Expected .decoding"); return }
    }
    @Test("clear resets to noImage")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testClear() {
        let vm = CodecInspectorViewModel(); vm.markDecoding(); vm.clear()
        guard case .noImage = vm.status else { Issue.record("Expected .noImage after clear"); return }
    }
    @Test("statusSummary after clear not decoding")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testSummaryClear() {
        let vm = CodecInspectorViewModel(); vm.clear()
        #expect(vm.statusSummary.isEmpty == false && vm.statusSummary.lowercased().contains("decoding") == false)
    }
    @Test("update sets decoded entry")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testUpdateDecoded() {
        let vm = CodecInspectorViewModel()
        let desc = PixelDataDescriptor(rows: 2, columns: 2, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            photometricInterpretation: .monochrome2)
        let result = DecodedImageResult(
            pixelData: PixelData(data: Data([0,0,0,0]), descriptor: desc),
            transferSyntaxUID: "1.2.840.10008.1.2.4.90",
            codecName: "J2KSwift", backend: .accelerate, decodeTimeMs: 23.5)
        vm.update(from: result, frameCount: 1)
        guard case .decoded(let e) = vm.status else { Issue.record("Expected .decoded"); return }
        #expect(e.codecName == "J2KSwift" && e.decodeTimeMs == 23.5 && e.frameCount == 1)
        // PS3.6 2026a Table A-1 name of .4.90 — not "Explicit VR Little Endian (…)".
        #expect(e.transferSyntaxDescription == "JPEG 2000 Image Compression (Lossless Only)")
    }
    @Test("update sets hasEntry true")
    @available(macOS 14.0, iOS 17.0, visionOS 1.0, *)
    func testHasEntryUpdate() {
        let vm = CodecInspectorViewModel()
        let desc = PixelDataDescriptor(rows: 1, columns: 1, numberOfFrames: 1,
            bitsAllocated: 8, bitsStored: 8, highBit: 7, isSigned: false,
            photometricInterpretation: .monochrome2)
        let result = DecodedImageResult(
            pixelData: PixelData(data: Data([0]), descriptor: desc),
            transferSyntaxUID: "1.2.840.10008.1.2.1",
            codecName: "Native", backend: .scalar, decodeTimeMs: 0.0)
        vm.update(from: result, frameCount: 5)
        #expect(vm.hasEntry == true)
    }
}

@Suite("ImageDecodingService")
struct ImageDecodingServiceTests {
    @Test("init creates service")
    func testInit() { _ = ImageDecodingService() }

    @Test("inspectorStatus minimal DICOM valid")
    func testInspectorStatus() throws {
        let data = try minimalDICOM()
        let file = try DICOMFile.read(from: data)
        let status = ImageDecodingService().inspectorStatus(for: file)
        switch status { case .noImage, .decoding, .decoded, .uncompressed, .unsupportedCodec: break }
    }

    private func minimalDICOM() throws -> Data {
        var d = Data()
        d.append(contentsOf: [UInt8](repeating: 0, count: 128))
        d.append(contentsOf: [0x44, 0x49, 0x43, 0x4D])
        func tag(_ g: UInt16, _ e: UInt16, _ vr: String, _ v: [UInt8]) -> Data {
            var x = Data()
            x += [UInt8(g & 0xFF), UInt8(g >> 8), UInt8(e & 0xFF), UInt8(e >> 8)]
            x += [UInt8](vr.utf8)
            let c = UInt16(v.count)
            x += [UInt8(c & 0xFF), UInt8(c >> 8)]
            x += v; return x
        }
        func uid(_ s: String) -> [UInt8] {
            let p = s.count % 2 == 0 ? s : s + "\u{0}"
            return Array(p.utf8)
        }
        var meta = Data()
        meta += tag(0x0002, 0x0001, "OB", [0x00, 0x01])
        meta += tag(0x0002, 0x0002, "UI", uid("1.2.840.10008.5.1.4.1.1.2"))
        meta += tag(0x0002, 0x0003, "UI", uid("1.2.3.4.5"))
        meta += tag(0x0002, 0x0010, "UI", uid("1.2.840.10008.1.2.1"))
        let ml = UInt32(meta.count)
        d += tag(0x0002, 0x0000, "UL", [UInt8(ml & 0xFF), UInt8(ml >> 8 & 0xFF), UInt8(ml >> 16 & 0xFF), UInt8(ml >> 24)])
        d += meta
        d += tag(0x0008, 0x0016, "UI", uid("1.2.840.10008.5.1.4.1.1.2"))
        d += tag(0x0008, 0x0018, "UI", uid("1.2.3.4.5"))
        return d
    }
}
