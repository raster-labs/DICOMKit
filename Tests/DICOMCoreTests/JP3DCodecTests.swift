import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit

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

    // MARK: - Codec Construction Tests

    @Test("JP3DCodec default construction uses lossless mode")
    func test_codec_defaultIsLossless() {
        let codec = JP3DCodec()
        switch codec.compressionMode {
        case .lossless:
            break // expected
        default:
            Issue.record("Expected lossless default, got different mode")
        }
    }

    @Test("JP3DCodec supported transfer syntaxes include both JP3D UIDs")
    func test_codec_supportedTransferSyntaxes() {
        #expect(JP3DCodec.supportedTransferSyntaxes.contains(TransferSyntax.jp3dLossless.uid))
        #expect(JP3DCodec.supportedTransferSyntaxes.contains(TransferSyntax.jp3dLossy.uid))
    }

    // MARK: - canEncode & Deferral Tests (pending SwiftJ2K 12.2.0 / SwiftJ2K3D)

    @Test("JP3DCodec reports canEncode == false while deferred pending SwiftJ2K 12.2.0")
    func test_canEncode_deferredReturnsFalse() {
        let codec = JP3DCodec()
        #expect(!codec.canEncode(with: .lossless, descriptor: grayscaleVolumeDescriptor()))
        #expect(!codec.canEncode(with: .lossless, descriptor: grayscale8VolumeDescriptor()))
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

    @Test("JP3DCodec is not registered in CodecRegistry while deferred pending SwiftJ2K 12.2.0")
    func test_codecRegistry_jp3dDeferred() {
        let registry = CodecRegistry.shared
        #expect(!registry.hasCodec(for: TransferSyntax.jp3dLossless.uid))
        #expect(!registry.hasCodec(for: TransferSyntax.jp3dLossy.uid))
        #expect(registry.encoder(for: TransferSyntax.jp3dLossless.uid) == nil)
        #expect(registry.encoder(for: TransferSyntax.jp3dLossy.uid) == nil)
    }

    // MARK: - Volumetric Fail-Closed Deferral Tests

    @Test("JP3DCodec async encodeVolume and decodeVolume fail closed with SwiftJ2K 12.2.0 deferral")
    func test_asyncEncodeDecode_failClosedWhileDeferred() async {
        let desc = grayscale8VolumeDescriptor(rows: 8, columns: 8, frames: 4)
        let original = makeGradientVolume(descriptor: desc)

        for mode: JP3DCodec.CompressionMode in [.lossless, .lossy(psnr: 40.0), .losslessHTJ2K] {
            let codec = JP3DCodec(compressionMode: mode)
            do {
                _ = try await codec.encodeVolume(original, descriptor: desc)
                Issue.record("Expected encodeVolume to fail closed while deferred")
            } catch let DICOMError.unsupportedTransferSyntax(reason) {
                #expect(reason.contains("SwiftJ2K 12.2.0"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }

            do {
                _ = try await codec.decodeVolume(Data([0x00, 0x01]), descriptor: desc)
                Issue.record("Expected decodeVolume to fail closed while deferred")
            } catch let DICOMError.unsupportedTransferSyntax(reason) {
                #expect(reason.contains("SwiftJ2K 12.2.0"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("JP3DCodec sync decode, decodeFrame, encode, and encodeFrame fail closed with SwiftJ2K 12.2.0 deferral")
    func test_syncMethods_failClosedWhileDeferred() {
        let codec = JP3DCodec(compressionMode: .lossless)
        let desc = grayscale8VolumeDescriptor(rows: 8, columns: 8, frames: 4)
        let original = makeGradientVolume(descriptor: desc)

        #expect(throws: DICOMError.self) {
            _ = try codec.decode(Data([0x00]), descriptor: desc)
        }
        #expect(throws: DICOMError.self) {
            _ = try codec.decodeFrame(Data([0x00]), descriptor: desc, frameIndex: 0)
        }
        #expect(throws: DICOMError.self) {
            _ = try codec.encode(original, descriptor: desc, configuration: .lossless)
        }
        #expect(throws: DICOMError.self) {
            _ = try codec.encodeFrame(original.prefix(desc.bytesPerFrame), descriptor: desc, frameIndex: 0, configuration: .lossless)
        }
    }
}
