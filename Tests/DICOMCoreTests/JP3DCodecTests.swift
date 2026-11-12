import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit
import SwiftJ2K3D

@Suite("JP3DCodec Tests")
struct JP3DCodecTests {

    // MARK: - Helpers

    private func grayscaleVolumeDescriptor(
        rows: Int = 16,
        columns: Int = 16,
        frames: Int = 4
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: frames,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
    }

    private func grayscale8VolumeDescriptor(
        rows: Int = 16,
        columns: Int = 16,
        frames: Int = 4
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: frames,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
    }

    /// Creates synthetic volume pixel data with a gradient pattern.
    private func makeGradientVolume(descriptor: PixelDataDescriptor) -> Data {
        let bytesPerPixel = descriptor.bitsAllocated / 8
        let totalPixels = descriptor.rows * descriptor.columns * descriptor.numberOfFrames
        var data = Data(capacity: totalPixels * bytesPerPixel)

        for frame in 0..<descriptor.numberOfFrames {
            for row in 0..<descriptor.rows {
                for col in 0..<descriptor.columns {
                    let value = UInt16((frame * 256 + row * 16 + col) & 0x0FFF)
                    if bytesPerPixel == 2 {
                        var le = value.littleEndian
                        data.append(Data(bytes: &le, count: 2))
                    } else {
                        data.append(UInt8(value & 0xFF))
                    }
                }
            }
        }
        return data
    }

    // MARK: - Codec Suite Engine Version Constants

    @Test("All 5 pure-Swift codec engines expose their 11 Nov 2026 release versions")
    func test_codecEngineVersions() {
        #expect(SwiftJ2KDICOMCodec.engineName == "SwiftJ2K")
        #expect(SwiftJ2KDICOMCodec.engineVersion == "12.2.0")
        #expect(JP3DCodec.engineName == "SwiftJ2K3D")
        #expect(JP3DCodec.engineVersion == "12.2.0")
        #expect(RLECodec.engineName == "SwiftRLE")
        #expect(RLECodec.engineVersion == "1.0.2")
        #expect(JPEGLSCodec.engineName == "SwiftJLS")
        #expect(JPEGLSCodec.engineVersion == "2.0.1")
        #expect(JLICodec.engineName == "SwiftJLI")
        #expect(JLICodec.engineVersion == "2.0.3")
        #expect(JXLCodec.engineName == "SwiftJXL")
        #expect(JXLCodec.engineVersion == "2.0.1")
    }

    // MARK: - Transfer Syntax Tests

    @Test("JP3D transfer syntaxes are registered correctly")
    func test_transferSyntax_jp3dRegistered() {
        let lossless = TransferSyntax.jp3dLossless
        #expect(lossless.uid == "1.2.826.0.1.3680043.10.511.1")
        #expect(lossless.isLossless)
        #expect(lossless.isJP3D)

        let lossy = TransferSyntax.jp3dLossy
        #expect(lossy.uid == "1.2.826.0.1.3680043.10.511.2")
        #expect(!lossy.isLossless)
        #expect(lossy.isJP3D)
    }

    @Test("JP3D transfer syntaxes can be looked up from UID")
    func test_transferSyntax_fromUID() {
        let lossless = TransferSyntax.from(uid: "1.2.826.0.1.3680043.10.511.1")
        #expect(lossless == .jp3dLossless)

        let lossy = TransferSyntax.from(uid: "1.2.826.0.1.3680043.10.511.2")
        #expect(lossy == .jp3dLossy)
    }

    @Test("JP3D transfer syntaxes can be parsed by name")
    func test_transferSyntax_parseByName() {
        #expect(TransferSyntax.parse("jp3d-lossless") == .jp3dLossless)
        #expect(TransferSyntax.parse("jp3dlossless") == .jp3dLossless)
        #expect(TransferSyntax.parse("jp3d") == .jp3dLossy)
        #expect(TransferSyntax.parse("jp3d-lossy") == .jp3dLossy)
        #expect(TransferSyntax.parse("jp3dlossy") == .jp3dLossy)
    }

    // MARK: - Codec Construction & Capability Tests

    @Test("JP3DCodec default construction uses lossless mode")
    func test_codec_defaultIsLossless() {
        let codec = JP3DCodec()
        switch codec.compressionMode {
        case .lossless:
            break
        default:
            Issue.record("Expected lossless default, got different mode")
        }
    }

    @Test("JP3DCodec supported transfer syntaxes include both JP3D UIDs")
    func test_codec_supportedTransferSyntaxes() {
        #expect(JP3DCodec.supportedTransferSyntaxes.contains(TransferSyntax.jp3dLossless.uid))
        #expect(JP3DCodec.supportedTransferSyntaxes.contains(TransferSyntax.jp3dLossy.uid))
    }

    @Test("JP3DCodec reports canEncode == true for 8-bit and 16-bit grayscale multi-frame volumes")
    func test_canEncode_supportedVolumes() {
        let codec = JP3DCodec()
        #expect(codec.canEncode(with: .lossless, descriptor: grayscaleVolumeDescriptor()))
        #expect(codec.canEncode(with: .lossless, descriptor: grayscale8VolumeDescriptor()))
    }

    @Test("JP3DCodec rejects single-frame images")
    func test_canEncode_rejectsSingleFrame() {
        let codec = JP3DCodec()
        let desc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        #expect(!codec.canEncode(with: .lossless, descriptor: desc))
    }

    @Test("JP3DCodec rejects color (RGB) volumes")
    func test_canEncode_rejectsRGB() {
        let codec = JP3DCodec()
        let desc = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 4,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        #expect(!codec.canEncode(with: .lossless, descriptor: desc))
    }

    // MARK: - Codec Registry Tests

    @Test("JP3DCodec is registered in CodecRegistry.shared for both JP3D UIDs")
    func test_codecRegistry_jp3dRegistered() {
        let registry = CodecRegistry.shared
        #expect(registry.hasCodec(for: TransferSyntax.jp3dLossless.uid))
        #expect(registry.hasCodec(for: TransferSyntax.jp3dLossy.uid))
        #expect(registry.encoder(for: TransferSyntax.jp3dLossless.uid) != nil)
        #expect(registry.encoder(for: TransferSyntax.jp3dLossy.uid) != nil)
    }

    // MARK: - Volumetric Round-Trip, Inspect, 3D ROI, and Transcode Tests

    @Test("JP3DCodec lossless 16-bit and 8-bit round-trip is bit-exact")
    func test_losslessRoundTrip_exact() async throws {
        let codec = JP3DCodec(compressionMode: .lossless)

        let desc16 = grayscaleVolumeDescriptor(rows: 16, columns: 16, frames: 4)
        let src16 = makeGradientVolume(descriptor: desc16)
        let enc16 = try await codec.encodeVolume(src16, descriptor: desc16)
        let dec16 = try await codec.decodeVolume(enc16, descriptor: desc16)
        #expect(dec16 == src16)

        let desc8 = grayscale8VolumeDescriptor(rows: 12, columns: 14, frames: 4)
        let src8 = makeGradientVolume(descriptor: desc8)
        let enc8 = try await codec.encodeVolume(src8, descriptor: desc8)
        let dec8 = try await codec.decodeVolume(enc8, descriptor: desc8)
        #expect(dec8 == src8)
    }

    @Test("JP3DCodec lossless HTJ2K round-trip and inspectVolume metadata")
    func test_losslessHTJ2K_and_inspect() async throws {
        let codec = JP3DCodec(compressionMode: .losslessHTJ2K)
        let desc = grayscaleVolumeDescriptor(rows: 16, columns: 12, frames: 4)
        let src = makeGradientVolume(descriptor: desc)

        let encoded = try await codec.encodeVolumeWithReport(src, descriptor: desc)
        let codestream = encoded.data
        #expect(!codestream.isEmpty)
        #expect(encoded.report.fidelity == .exactSamples)

        let info = try codec.inspectVolume(codestream)
        #expect(info.width == 12)
        #expect(info.height == 16)
        #expect(info.depth == 4)
        #expect(info.bitDepth == 12)
        #expect(info.isHTJ2K)
        #expect(info.isLossless)

        let decoded = try await codec.decodeVolume(codestream, descriptor: desc)
        #expect(decoded == src)
    }

    @Test("JP3DCodec lossy encode/decode produces valid reconstructed volume")
    func test_lossyRoundTrip() async throws {
        let codec = JP3DCodec(compressionMode: .lossy(psnr: 45.0))
        let desc = grayscaleVolumeDescriptor(rows: 16, columns: 16, frames: 4)
        let src = makeGradientVolume(descriptor: desc)

        let codestream = try await codec.encodeVolume(src, descriptor: desc)
        let decoded = try await codec.decodeVolume(codestream, descriptor: desc)
        #expect(decoded.count == src.count)
    }

    @Test("JP3DCodec decodeVolumeRegion extracts exact 3D sub-volume")
    func test_decodeVolumeRegion_exactSubvolume() async throws {
        let codec = JP3DCodec(compressionMode: .lossless)
        let desc = grayscaleVolumeDescriptor(rows: 16, columns: 16, frames: 4)
        let src = makeGradientVolume(descriptor: desc)
        let codestream = try await codec.encodeVolume(src, descriptor: desc)

        let region = JP3DRegion(originX: 4, originY: 2, originZ: 1, width: 6, height: 5, depth: 2)
        let roiResult = try await codec.decodeVolumeRegion(codestream, descriptor: desc, region: region)
        let roiBytes = roiResult.data
        #expect(roiResult.width == 6)
        #expect(roiResult.height == 5)
        #expect(roiResult.depth == 2)
        let expectedByteCount = 120 // 6 * 5 * 2 voxels * 2 bytes
        #expect(roiBytes.count == expectedByteCount)

        // Compare against expected sub-cube from `src`
        var expected = Data(capacity: roiBytes.count)
        for z in 1..<3 {
            for y in 2..<7 {
                for x in 4..<10 {
                    let voxelOffset = ((z * 16 + y) * 16 + x) * 2
                    expected.append(src.subdata(in: voxelOffset..<(voxelOffset + 2)))
                }
            }
        }
        #expect(roiBytes == expected)
    }

    @Test("JP3DCodec transcodeVolume losslessly converts J2K <-> HTJ2K in the wavelet domain")
    func test_transcodeVolume_j2k_htj2k_roundTrip() async throws {
        let j2kCodec = JP3DCodec(compressionMode: .lossless)
        let desc = grayscaleVolumeDescriptor(rows: 16, columns: 16, frames: 4)
        let src = makeGradientVolume(descriptor: desc)

        let j2kStream = try await j2kCodec.encodeVolume(src, descriptor: desc)
        let j2kInfo = try j2kCodec.inspectVolume(j2kStream)
        #expect(!j2kInfo.isHTJ2K)

        let htj2kStream = try await j2kCodec.transcodeVolume(j2kStream, toHTJ2K: true)
        let htj2kInfo = try j2kCodec.inspectVolume(htj2kStream)
        #expect(htj2kInfo.isHTJ2K)
        let decodedHT = try await j2kCodec.decodeVolume(htj2kStream, descriptor: desc)
        #expect(decodedHT == src)

        let backToJ2K = try await j2kCodec.transcodeVolume(htj2kStream, toHTJ2K: false)
        let backInfo = try j2kCodec.inspectVolume(backToJ2K)
        #expect(!backInfo.isHTJ2K)
        let decodedBack = try await j2kCodec.decodeVolume(backToJ2K, descriptor: desc)
        #expect(decodedBack == src)
    }

    @Test("JP3DCodec synchronous ImageCodec/ImageEncoder bridge works without deadlocking")
    func test_syncBridge_encodeAndDecode() throws {
        let codec = JP3DCodec(compressionMode: .lossless)
        let desc = grayscale8VolumeDescriptor(rows: 8, columns: 8, frames: 4)
        let src = makeGradientVolume(descriptor: desc)

        let fragments = try codec.encode(src, descriptor: desc, configuration: .lossless)
        #expect(fragments.count == 1)

        let fullDecoded = try codec.decode(fragments[0], descriptor: desc)
        #expect(fullDecoded == src)

        let slice2 = try codec.decodeFrame(fragments[0], descriptor: desc, frameIndex: 2)
        let expectedSlice2 = src.subdata(in: (2 * 64)..<(3 * 64))
        #expect(slice2 == expectedSlice2)
    }
}
