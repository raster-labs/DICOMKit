import Testing
import Foundation
import DICOMKit
@testable import DICOMCore

/// Verifies that `dicom-compress` (via `CompressionManager.codecMap`) exposes every
/// transfer syntax the shared DICOMKit compression engine can actually produce — so
/// the DICOMStudio CLI Workshop codec picker (which now derives its list straight from
/// `CompressionManager.supportedCodecs()`) and the `dicom-compress` CLI stay in lock
/// step with the registered `CodecRegistry` encoders.
///
/// Anchors the four JPEG Swift libraries integrated into DICOMCore:
///   • SwiftJLI → JPEG (baseline / extended / lossless / SV1)
///   • SwiftJ2K → JPEG 2000 / HTJ2K
///   • SwiftJLS → JPEG-LS        ← was registered but UNREACHABLE from the codec map
///   • JXLSwift → JPEG XL
@Suite("dicom-compress codec map ↔ DICOMCore encoder parity")
struct CompressionCodecMapTests {

    /// JPEG-LS (the SwiftJLS library) must be selectable through the codec map. Both
    /// UIDs — lossless `.80` and near-lossless `.81` — must resolve to the right
    /// transfer syntax and have a registered encoder.
    @Test("Codec map exposes JPEG-LS (SwiftJLS) for both lossless and near-lossless")
    func codecMapExposesJPEGLS() {
        #expect(CompressionManager.transferSyntax(for: "jpeg-ls-lossless")?.uid
                == TransferSyntax.jpegLSLossless.uid)
        #expect(CompressionManager.transferSyntax(for: "jls-lossless")?.uid
                == TransferSyntax.jpegLSLossless.uid)
        #expect(CompressionManager.transferSyntax(for: "jpeg-ls")?.uid
                == TransferSyntax.jpegLSNearLossless.uid)
        #expect(CompressionManager.transferSyntax(for: "jls")?.uid
                == TransferSyntax.jpegLSNearLossless.uid)

        let registry = CodecRegistry.shared
        #expect(registry.hasEncoder(for: TransferSyntax.jpegLSLossless.uid))
        #expect(registry.hasEncoder(for: TransferSyntax.jpegLSNearLossless.uid))
    }

    /// Every compressed (encapsulated) codec the map advertises must have a registered
    /// encoder — otherwise the picker/CLI would offer a target the engine can't produce
    /// (the exact gap JPEG-LS had). Uncompressed targets (explicit/implicit/deflate) are
    /// handled by the serializer directly and intentionally have no encoder.
    @Test("Every encodable encapsulated codec in the map has a registered encoder")
    func everyCompressedCodecHasAnEncoder() {
        let registry = CodecRegistry.shared
        for codec in CompressionManager.supportedCodecs() where codec.syntax.isEncapsulated {
            // JPEG 2000 Part-2 is deliberately decode-only (its MCT cannot be inverted
            // by the pinned library), so it is advertised for a clear rejection message
            // but has no registered encoder. Every other advertised codec must encode.
            if J2KRoutePlanner.unsupportedEncodeReason(transferSyntaxUID: codec.syntax.uid) != nil {
                #expect(registry.hasEncoder(for: codec.syntax.uid) == false)
                continue
            }
            #expect(registry.hasEncoder(for: codec.syntax.uid),
                    "codec '\(codec.name)' (\(codec.syntax.uid)) is advertised but has no registered encoder")
        }
    }

    /// All four JPEG Swift libraries are reachable end-to-end through the codec map:
    /// a user-facing codec name resolves to the expected transfer syntax, which has a
    /// registered encoder.
    @Test("All four JPEG Swift libraries are reachable through the codec map",
          arguments: [
            ("jpeg-baseline", TransferSyntax.jpegBaseline.uid),          // SwiftJLI
            ("jpeg-extended", TransferSyntax.jpegExtended.uid),          // SwiftJLI
            ("jpeg-lossless", TransferSyntax.jpegLossless.uid),          // SwiftJLI
            ("jpeg-lossless-sv1", TransferSyntax.jpegLosslessSV1.uid),   // SwiftJLI
            ("jpeg2000", TransferSyntax.jpeg2000.uid),                   // SwiftJ2K (.91 lossy)
            ("jpeg2000-lossless", TransferSyntax.jpeg2000.uid),          // SwiftJ2K (.91 reversible)
            ("jpeg2000-lossless-only", TransferSyntax.jpeg2000Lossless.uid), // SwiftJ2K (.90)
            ("htj2k-lossless", TransferSyntax.htj2kLossy.uid),           // SwiftJ2K (HTJ2KCodec, .203 reversible)
            ("htj2k-lossless-only", TransferSyntax.htj2kLossless.uid),   // SwiftJ2K (HTJ2KCodec, .201)
            ("jpeg-ls-lossless", TransferSyntax.jpegLSLossless.uid),     // SwiftJLS
            ("jpeg-ls", TransferSyntax.jpegLSNearLossless.uid),          // SwiftJLS
            ("jpeg-xl-lossless", TransferSyntax.jpegXL.uid),             // JXLSwift (.112 reversible, Modular)
            ("jpeg-xl-lossless-only", TransferSyntax.jpegXLLossless.uid),// JXLSwift (.110)
            ("jpeg-xl", TransferSyntax.jpegXL.uid),                      // JXLSwift (.112 lossy, VarDCT)
          ])
    func allFourLibrariesReachable(codec: String, expectedUID: String) {
        #expect(CompressionManager.transferSyntax(for: codec)?.uid == expectedUID,
                "codec '\(codec)' did not resolve to \(expectedUID)")
        #expect(CodecRegistry.shared.hasEncoder(for: expectedUID),
                "no encoder registered for '\(codec)' (\(expectedUID))")
    }

    /// End-to-end proof that selecting the JPEG-LS codec actually drives the JLSwift
    /// encoder through the shared `CompressionManager.compressData` path — the same
    /// in-memory entry point DICOMStudio and the `dicom-compress` CLI both use. The
    /// output must be encapsulated and carry the JPEG-LS Lossless transfer syntax.
    @Test("compressData --codec jpeg-ls-lossless produces an encapsulated JPEG-LS file")
    func compressToJPEGLSEndToEnd() throws {
        let manager = CompressionManager()
        let uncompressed = try uncompressedDICOM(rows: 64, columns: 64, bitsAllocated: 8)

        let compressed = try manager.compressData(uncompressed, codec: "jpeg-ls-lossless", quality: nil)
        let info = try manager.getCompressionInfo(data: compressed)

        #expect(info.transferSyntaxUID == TransferSyntax.jpegLSLossless.uid)
        #expect(info.isCompressed)
        #expect(info.isJPEGLS)          // info labels it JPEG-LS, not "None (uncompressed)"
        #expect(!info.isJPEG)
        let size = try #require(info.pixelDataSize)
        #expect(size > 0)
        #expect(size <= 64 * 64)   // a real compressed payload, not the raw bytes
    }

    // MARK: - Fixture

    /// Minimal uncompressed (Explicit VR LE) DICOM file as bytes — a constant image
    /// so any lossless codec compresses it well below the source size.
    private func uncompressedDICOM(rows: UInt16, columns: UInt16,
                                   bitsAllocated: UInt16) throws -> Data {
        var dataSet = DataSet()
        dataSet.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.6.7.8.9", for: .sopInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.100", for: .studyInstanceUID, vr: .UI)
        dataSet.setString("1.2.3.4.5.200", for: .seriesInstanceUID, vr: .UI)
        dataSet.setUInt16(rows, for: .rows)
        dataSet.setUInt16(columns, for: .columns)
        dataSet.setUInt16(bitsAllocated, for: .bitsAllocated)
        dataSet.setUInt16(bitsAllocated, for: .bitsStored)
        dataSet.setUInt16(bitsAllocated - 1, for: .highBit)
        dataSet.setUInt16(0, for: .pixelRepresentation)
        dataSet.setUInt16(1, for: .samplesPerPixel)
        dataSet.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)

        let pixelByteCount = Int(rows) * Int(columns) * (Int(bitsAllocated) / 8)
        let pixelData = Data(repeating: 128, count: pixelByteCount)
        let vr: VR = bitsAllocated <= 8 ? .OB : .OW
        dataSet[.pixelData] = DataElement.data(tag: .pixelData, vr: vr, data: pixelData)

        return try DICOMFile.create(dataSet: dataSet).write()
    }
}
