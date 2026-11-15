import Foundation
import Testing
@testable import DICOMCore

@Suite("Sibling Codec Hardware Acceleration & Worker Controls")
struct SiblingCodecAccelerationTests {

    private func makeDescriptor(
        width: Int,
        height: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        isSigned: Bool = false,
        spp: Int = 1,
        planarConfiguration: Int = 0
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            highBit: bitsStored - 1,
            isSigned: isSigned,
            samplesPerPixel: spp,
            photometricInterpretation: spp == 1 ? .monochrome2 : .rgb,
            planarConfiguration: planarConfiguration
        )
    }

    private func makeFrame(
        width: Int,
        height: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        isSigned: Bool = false,
        spp: Int = 1,
        planarConfiguration: Int = 0
    ) -> Data {
        let bytesPerSample = bitsAllocated / 8
        let mask = (1 << bitsStored) - 1
        let signBit = 1 << (bitsStored - 1)
        var data = Data(count: width * height * spp * bytesPerSample)
        data.withUnsafeMutableBytes { raw in
            let dst = raw.bindMemory(to: UInt8.self)
            if planarConfiguration == 1 && spp > 1 {
                var idx = 0
                for c in 0..<spp {
                    for y in 0..<height {
                        for x in 0..<width {
                            let sample = ((x * 11 + y * 19 + c * 47) ^ ((x &+ c) &* (y &+ 3))) & mask
                            if bytesPerSample == 1 {
                                dst[idx] = UInt8(truncatingIfNeeded: sample)
                                idx += 1
                            } else {
                                let stored: UInt16
                                if isSigned && (sample & signBit) != 0 {
                                    stored = UInt16(bitPattern: Int16(sample - (1 << bitsStored)))
                                } else {
                                    stored = UInt16(truncatingIfNeeded: sample)
                                }
                                dst[idx] = UInt8(stored & 0xFF)
                                dst[idx + 1] = UInt8((stored >> 8) & 0xFF)
                                idx += 2
                            }
                        }
                    }
                }
            } else {
                var idx = 0
                for y in 0..<height {
                    for x in 0..<width {
                        for c in 0..<spp {
                            let sample = ((x * 11 + y * 19 + c * 47) ^ ((x &+ c) &* (y &+ 3))) & mask
                            if bytesPerSample == 1 {
                                dst[idx] = UInt8(truncatingIfNeeded: sample)
                                idx += 1
                            } else {
                                let stored: UInt16
                                if isSigned && (sample & signBit) != 0 {
                                    stored = UInt16(bitPattern: Int16(sample - (1 << bitsStored)))
                                } else {
                                    stored = UInt16(truncatingIfNeeded: sample)
                                }
                                dst[idx] = UInt8(stored & 0xFF)
                                dst[idx + 1] = UInt8((stored >> 8) & 0xFF)
                                idx += 2
                            }
                        }
                    }
                }
            }
        }
        return data
    }

    private func containsJPEGMarker(_ data: Data, secondByte: UInt8) -> Bool {
        guard data.count >= 2 else { return false }
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<(bytes.count - 1) {
                if bytes[i] == 0xFF && bytes[i + 1] == secondByte {
                    return true
                }
            }
            return false
        }
    }

    @Test("CodecRegistry propagates decodeBackend to RLE, JPEG-LS, JLI, and JXL codecs and keeps Metal support truthful")
    func registryBackendPropagationAndTruthfulMetalSupport() {
        #expect(!RLECodec.supportsBackend(.metal))
        #expect(RLECodec.supportsBackend(.accelerate))
        #expect(RLECodec.supportsBackend(.scalar))

        #expect(!JPEGLSCodec.supportsBackend(.metal))
        #expect(JPEGLSCodec.supportsBackend(.accelerate))
        #expect(JPEGLSCodec.supportsBackend(.scalar))

        #expect(!JLICodec.supportsBackend(.metal))
        #expect(JLICodec.supportsBackend(.accelerate))
        #expect(JLICodec.supportsBackend(.scalar))

        #expect(!JXLCodec.supportsBackend(.metal))
        #expect(JXLCodec.supportsBackend(.accelerate))
        #expect(JXLCodec.supportsBackend(.scalar))

        let rleScalar = CodecRegistry.shared.resolveDecoder(
            for: TransferSyntax.rleLossless.uid,
            decodeBackend: .scalar
        )?.codec as? RLECodec
        #expect(rleScalar?.decodeBackend == .scalar)

        let jlsAccel = CodecRegistry.shared.resolveDecoder(
            for: TransferSyntax.jpegLSLossless.uid,
            decodeBackend: .accelerate
        )?.codec as? JPEGLSCodec
        #expect(jlsAccel?.decodeBackend == .accelerate)

        let jliScalar = CodecRegistry.shared.resolveDecoder(
            for: TransferSyntax.jpegLosslessSV1.uid,
            decodeBackend: .scalar
        )?.codec as? JLICodec
        #expect(jliScalar?.decodeBackend == .scalar)

        let jxlAccel = CodecRegistry.shared.resolveDecoder(
            for: TransferSyntax.jpegXLLossless.uid,
            decodeBackend: .accelerate
        )?.codec as? JXLCodec
        #expect(jxlAccel?.decodeBackend == .accelerate)
    }

    @Test("RLECodec 1T scalar and 10T accelerated paths are bit-exact across 16-bit mono and 8-bit RGB")
    func rleScalarVsAcceleratedParity() throws {
        let monoDesc = makeDescriptor(width: 257, height: 193, bitsAllocated: 16, bitsStored: 12)
        let monoRaw = makeFrame(width: 257, height: 193, bitsAllocated: 16, bitsStored: 12)

        let rle1T = RLECodec(decodeBackend: .scalar, maximumWorkers: 1)
        let rle10T = RLECodec(decodeBackend: .accelerate, maximumWorkers: 10)

        let encoded1T = try rle1T.encodeFrame(monoRaw, descriptor: monoDesc, frameIndex: 0, configuration: .lossless)
        let encoded10T = try rle10T.encodeFrame(monoRaw, descriptor: monoDesc, frameIndex: 0, configuration: .lossless)
        #expect(encoded1T == encoded10T)

        let decoded1T = try rle1T.decodeFrame(encoded10T, descriptor: monoDesc, frameIndex: 0)
        let decoded10T = try rle10T.decodeFrame(encoded1T, descriptor: monoDesc, frameIndex: 0)
        #expect(decoded1T == monoRaw)
        #expect(decoded10T == monoRaw)

        let rgbDesc = makeDescriptor(width: 180, height: 140, bitsAllocated: 8, bitsStored: 8, spp: 3)
        let rgbRaw = makeFrame(width: 180, height: 140, bitsAllocated: 8, bitsStored: 8, spp: 3)
        let rgbEncoded = try rle10T.encodeFrame(rgbRaw, descriptor: rgbDesc, frameIndex: 0, configuration: .lossless)
        #expect(try rle1T.decodeFrame(rgbEncoded, descriptor: rgbDesc, frameIndex: 0) == rgbRaw)
        #expect(try rle10T.decodeFrame(rgbEncoded, descriptor: rgbDesc, frameIndex: 0) == rgbRaw)
    }

    @Test("JPEGLSCodec keeps default restartIntervalLines=0 and parallelizes ILV=0 planes and explicit DRI strips bit-exactly")
    func jpegLSDefaultAndRestartIntervalParity() throws {
        let monoDesc = makeDescriptor(width: 256, height: 256, bitsAllocated: 16, bitsStored: 12)
        let monoRaw = makeFrame(width: 256, height: 256, bitsAllocated: 16, bitsStored: 12)

        let defaultCodec = JPEGLSCodec(decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid)
        #expect(defaultCodec.restartIntervalLines == 0)

        let defaultStream = try defaultCodec.encodeFrame(monoRaw, descriptor: monoDesc, frameIndex: 0, configuration: .lossless)
        #expect(!containsJPEGMarker(defaultStream, secondByte: 0xDD))

        let driCodec10T = JPEGLSCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10,
            restartIntervalLines: 32
        )
        let driCodec1T = JPEGLSCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegLSLossless.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1,
            restartIntervalLines: 32
        )

        let driStream10T = try driCodec10T.encodeFrame(monoRaw, descriptor: monoDesc, frameIndex: 0, configuration: .lossless)
        let driStream1T = try driCodec1T.encodeFrame(monoRaw, descriptor: monoDesc, frameIndex: 0, configuration: .lossless)
        #expect(containsJPEGMarker(driStream10T, secondByte: 0xDD))
        #expect(driStream10T == driStream1T)

        #expect(try driCodec1T.decodeFrame(driStream10T, descriptor: monoDesc, frameIndex: 0) == monoRaw)
        #expect(try driCodec10T.decodeFrame(driStream1T, descriptor: monoDesc, frameIndex: 0) == monoRaw)

        // Planar RGB (ILV=0) parallel component encode/decode parity
        let planarRGBDesc = makeDescriptor(width: 192, height: 144, bitsAllocated: 8, bitsStored: 8, spp: 3, planarConfiguration: 1)
        let planarRGBRaw = makeFrame(width: 192, height: 144, bitsAllocated: 8, bitsStored: 8, spp: 3, planarConfiguration: 1)
        let planarStream = try driCodec10T.withRestartIntervalLines(0)
            .encodeFrame(planarRGBRaw, descriptor: planarRGBDesc, frameIndex: 0, configuration: .lossless)
        #expect(try driCodec1T.decodeFrame(planarStream, descriptor: planarRGBDesc, frameIndex: 0) == planarRGBRaw)
        #expect(try driCodec10T.decodeFrame(planarStream, descriptor: planarRGBDesc, frameIndex: 0) == planarRGBRaw)
    }

    @Test("JLICodec keeps default restartInterval=0 and parallelizes explicit DRI strips across lossless SV1 and baseline lossy")
    func jliDefaultAndRestartIntervalParity() throws {
        let sv1Desc = makeDescriptor(width: 253, height: 256, bitsAllocated: 16, bitsStored: 12)
        let sv1Raw = makeFrame(width: 253, height: 256, bitsAllocated: 16, bitsStored: 12)

        let defaultSV1 = JLICodec(encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid)
        #expect(defaultSV1.restartInterval == 0)
        #expect(defaultSV1.restartIntervalRows == 0)
        let noDriStream = try defaultSV1.encodeFrame(sv1Raw, descriptor: sv1Desc, frameIndex: 0, configuration: .lossless)
        #expect(!containsJPEGMarker(noDriStream, secondByte: 0xDD))

        let sv1_10T = JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10,
            restartIntervalRows: 64
        )
        let sv1_1T = JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpegLosslessSV1.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1,
            restartIntervalRows: 64
        )

        let driStream10T = try sv1_10T.encodeFrame(sv1Raw, descriptor: sv1Desc, frameIndex: 0, configuration: .lossless)
        let driStream1T = try sv1_1T.encodeFrame(sv1Raw, descriptor: sv1Desc, frameIndex: 0, configuration: .lossless)
        #expect(containsJPEGMarker(driStream10T, secondByte: 0xDD))
        #expect(driStream10T == driStream1T)
        #expect(try sv1_1T.decodeFrame(driStream10T, descriptor: sv1Desc, frameIndex: 0) == sv1Raw)
        #expect(try sv1_10T.decodeFrame(driStream1T, descriptor: sv1Desc, frameIndex: 0) == sv1Raw)

        // Baseline lossy (.50) with restart intervals: 1T vs 10T on same backend is byte-exact,
        // and scalar integer IDCT vs accelerated float IDCT stays within ITU-T T.83 ±1 LSB.
        let lossyDesc = makeDescriptor(width: 256, height: 256, bitsAllocated: 8, bitsStored: 8)
        let lossyRaw = makeFrame(width: 256, height: 256, bitsAllocated: 8, bitsStored: 8)
        let baselineAccel10T = JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10,
            restartIntervalRows: 8
        )
        let baselineAccel1T = JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 1,
            restartIntervalRows: 8
        )
        let baselineScalar1T = JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1,
            restartIntervalRows: 8
        )
        let highCfg = CompressionConfiguration(quality: .high, speed: .balanced, preferLossless: false)
        let lossyStream = try baselineAccel10T.encodeFrame(lossyRaw, descriptor: lossyDesc, frameIndex: 0, configuration: highCfg)
        #expect(containsJPEGMarker(lossyStream, secondByte: 0xDD))
        let lossyDecAccel10T = try baselineAccel10T.decodeFrame(lossyStream, descriptor: lossyDesc, frameIndex: 0)
        let lossyDecAccel1T = try baselineAccel1T.decodeFrame(lossyStream, descriptor: lossyDesc, frameIndex: 0)
        let lossyDecScalar1T = try baselineScalar1T.decodeFrame(lossyStream, descriptor: lossyDesc, frameIndex: 0)
        #expect(lossyDecAccel10T == lossyDecAccel1T)
        let maxIDCTDiff = zip(lossyDecAccel10T, lossyDecScalar1T).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        #expect(maxIDCTDiff <= 1)
    }

    @Test("JXLCodec 1T vs 10T parity for Modular (.110), jbrd (.111), and >4 MiP extended VarDCT (.112)")
    func jxlMultiGroupAndExtendedVarDCT() throws {
        // 1. Multi-group signed 16-bit CT Modular lossless (.110)
        let ctDesc = makeDescriptor(width: 600, height: 520, bitsAllocated: 16, bitsStored: 16, isSigned: true)
        let ctRaw = makeFrame(width: 600, height: 520, bitsAllocated: 16, bitsStored: 16, isSigned: true)

        let jxlLossless1T = JXLCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid,
            encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1
        )
        let jxlLossless10T = JXLCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid,
            encodingTransferSyntaxUID: TransferSyntax.jpegXLLossless.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10
        )

        let modular1T = try jxlLossless1T.encodeFrame(ctRaw, descriptor: ctDesc, frameIndex: 0, configuration: .lossless)
        let modular10T = try jxlLossless10T.encodeFrame(ctRaw, descriptor: ctDesc, frameIndex: 0, configuration: .lossless)
        #expect(modular1T == modular10T)
        #expect(try jxlLossless1T.decodeFrame(modular10T, descriptor: ctDesc, frameIndex: 0) == ctRaw)
        #expect(try jxlLossless10T.decodeFrame(modular1T, descriptor: ctDesc, frameIndex: 0) == ctRaw)

        // 2. Multi-group JPEG recompression (.111 jbrd)
        let jpegDesc = makeDescriptor(width: 560, height: 520, bitsAllocated: 8, bitsStored: 8)
        let jpegRaw = makeFrame(width: 560, height: 520, bitsAllocated: 8, bitsStored: 8)
        let highCfg = CompressionConfiguration(quality: .high, speed: .balanced, preferLossless: false)
        let baselineJPEG = try JLICodec(
            encodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid
        ).encodeFrame(jpegRaw, descriptor: jpegDesc, frameIndex: 0, configuration: highCfg)

        let jbrd10T = try JXLCodec.recompressJPEGFragment(baselineJPEG, maximumWorkers: 10)
        let jbrd1T = try JXLCodec.recompressJPEGFragment(baselineJPEG, maximumWorkers: 1)
        #expect(jbrd10T == jbrd1T)
        #expect(try JXLCodec.reconstructJPEGFragment(jbrd10T, maximumWorkers: 1) == baselineJPEG)
        #expect(try JXLCodec.reconstructJPEGFragment(jbrd10T, maximumWorkers: 10) == baselineJPEG)

        let jxlRecompDec10T = JXLCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegXLRecompression.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10
        )
        let jxlRecompDec1T = JXLCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegXLRecompression.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1
        )
        let expectedAccelPixels = try JLICodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10
        ).decodeFrame(baselineJPEG, descriptor: jpegDesc, frameIndex: 0)
        let expectedScalarPixels = try JLICodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegBaseline.uid,
            decodeBackend: .scalar,
            maximumWorkers: 1
        ).decodeFrame(baselineJPEG, descriptor: jpegDesc, frameIndex: 0)
        let jbrdDec10T = try jxlRecompDec10T.decodeFrame(jbrd10T, descriptor: jpegDesc, frameIndex: 0)
        let jbrdDec1T = try jxlRecompDec1T.decodeFrame(jbrd10T, descriptor: jpegDesc, frameIndex: 0)
        #expect(jbrdDec10T == expectedAccelPixels)
        #expect(jbrdDec1T == expectedScalarPixels)
        let jbrdIDCTDiff = zip(jbrdDec10T, jbrdDec1T).reduce(0) { max($0, abs(Int($1.0) - Int($1.1))) }
        #expect(jbrdIDCTDiff <= 1)

        // 3. Extended >4 MiP (2560 x 2048 = 5.24 MiP) and >4096-axis (4104 x 16) VarDCT lossy (.112)
        let dxDesc = makeDescriptor(width: 2560, height: 2048, bitsAllocated: 8, bitsStored: 8)
        let dxRaw = makeFrame(width: 2560, height: 2048, bitsAllocated: 8, bitsStored: 8)
        let fastLossyCfg = CompressionConfiguration(quality: .high, speed: .fast, preferLossless: false)
        let jxlLossy10T = JXLCodec(
            decodingTransferSyntaxUID: TransferSyntax.jpegXL.uid,
            encodingTransferSyntaxUID: TransferSyntax.jpegXL.uid,
            decodeBackend: .accelerate,
            maximumWorkers: 10,
            allowExtendedVarDCT: true
        )
        let vardctStream = try jxlLossy10T.encodeFrame(dxRaw, descriptor: dxDesc, frameIndex: 0, configuration: fastLossyCfg)
        let decodedVarDCT = try jxlLossy10T.decodeFrame(vardctStream, descriptor: dxDesc, frameIndex: 0)
        #expect(decodedVarDCT.count == dxRaw.count)
        #expect(decodedVarDCT != dxRaw) // Confirms true lossy VarDCT rather than lossless Modular fallback

        let wideDesc = makeDescriptor(width: 4104, height: 16, bitsAllocated: 8, bitsStored: 8)
        let wideRaw = makeFrame(width: 4104, height: 16, bitsAllocated: 8, bitsStored: 8)
        let wideVarDCT = try jxlLossy10T.encodeFrame(wideRaw, descriptor: wideDesc, frameIndex: 0, configuration: highCfg)
        let decodedWideVarDCT = try jxlLossy10T.decodeFrame(wideVarDCT, descriptor: wideDesc, frameIndex: 0)
        #expect(decodedWideVarDCT.count == wideRaw.count)
        #expect(decodedWideVarDCT != wideRaw)
    }
}
