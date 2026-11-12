import Testing
import Foundation
import SwiftJLS
@testable import DICOMCore

@Suite("JPEGLSCodec Tests")
struct JPEGLSCodecTests {
    
    @Test("JPEG-LS codec supports correct transfer syntaxes")
    func testSupportedTransferSyntaxes() {
        let supported = JPEGLSCodec.supportedTransferSyntaxes
        
        #expect(supported.contains("1.2.840.10008.1.2.4.80"))
        #expect(supported.contains("1.2.840.10008.1.2.4.81"))
        #expect(supported.count == 2)
    }
    
    @Test("JPEG-LS codec supports encoding transfer syntaxes")
    func testSupportedEncodingTransferSyntaxes() {
        let supported = JPEGLSCodec.supportedEncodingTransferSyntaxes
        
        #expect(supported.contains("1.2.840.10008.1.2.4.80"))
        #expect(supported.contains("1.2.840.10008.1.2.4.81"))
        #expect(supported.count == 2)
    }
    
    @Test("JPEG-LS codec can encode 8-bit grayscale")
    func testCanEncode8BitGrayscale() {
        let codec = JPEGLSCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64, columns: 64,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        #expect(codec.canEncode(with: .default, descriptor: descriptor) == true)
        #expect(codec.canEncode(with: .lossless, descriptor: descriptor) == true)
    }
    
    @Test("JPEG-LS codec can encode 16-bit grayscale")
    func testCanEncode16BitGrayscale() {
        let codec = JPEGLSCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64, columns: 64,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        #expect(codec.canEncode(with: .default, descriptor: descriptor) == true)
    }
    
    @Test("JPEG-LS codec can encode RGB")
    func testCanEncodeRGB() {
        let codec = JPEGLSCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64, columns: 64,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        
        #expect(codec.canEncode(with: .default, descriptor: descriptor) == true)
    }
    
    @Test("JPEG-LS codec cannot encode unsupported bit depths")
    func testCannotEncodeUnsupportedBitDepths() {
        let codec = JPEGLSCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64, columns: 64,
            bitsAllocated: 32, bitsStored: 32, highBit: 31,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        #expect(codec.canEncode(with: .default, descriptor: descriptor) == false)
    }
    
    @Test("JPEG-LS decode empty data throws error")
    func testDecodeEmptyData() {
        let codec = JPEGLSCodec()
        let descriptor = PixelDataDescriptor(
            rows: 4, columns: 4,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        #expect(throws: DICOMError.self) {
            try codec.decodeFrame(Data(), descriptor: descriptor, frameIndex: 0)
        }
    }
    
    @Test("JPEG-LS lossless encode-decode roundtrip for 8-bit grayscale")
    func testLosslessRoundtrip8BitGrayscale() throws {
        let codec = JPEGLSCodec()
        let width = 8
        let height = 8
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create test image with a gradient pattern
        var pixelData = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixelData[y * width + x] = UInt8((x + y * width) % 256)
            }
        }
        
        // Encode
        let config = CompressionConfiguration.lossless
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        
        // Verify encoded data starts with SOI marker
        #expect(encoded.count >= 2)
        #expect(encoded[0] == 0xFF)
        #expect(encoded[1] == 0xD8)
        
        // Verify encoded data is compressed (should be smaller or at least have JPEG-LS structure)
        #expect(encoded.count > 0)
        
        // Decode
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        
        // Verify lossless roundtrip
        #expect(decoded.count == pixelData.count)
        for i in 0..<pixelData.count {
            #expect(decoded[i] == pixelData[i], "Mismatch at index \(i): expected \(pixelData[i]), got \(decoded[i])")
        }
    }
    
    @Test("JPEG-LS lossless encode-decode roundtrip for constant image")
    func testLosslessRoundtripConstantImage() throws {
        let codec = JPEGLSCodec()
        let width = 16
        let height = 16
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create constant image (all same value) - tests run mode
        let pixelData = Data(repeating: 128, count: width * height)
        
        let config = CompressionConfiguration.lossless
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        
        #expect(decoded.count == pixelData.count)
        for i in 0..<pixelData.count {
            #expect(decoded[i] == pixelData[i])
        }
    }
    
    @Test("JPEG-LS lossless encode-decode roundtrip for 16-bit grayscale")
    func testLosslessRoundtrip16BitGrayscale() throws {
        let codec = JPEGLSCodec()
        let width = 8
        let height = 8
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 16, bitsStored: 12, highBit: 11,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create 16-bit test image with values up to 4095 (12-bit)
        var pixelData = Data(count: width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt16((x + y * width) * 64 % 4096)
                let index = (y * width + x) * 2
                pixelData[index] = UInt8(value & 0xFF)
                pixelData[index + 1] = UInt8((value >> 8) & 0xFF)
            }
        }
        
        let config = CompressionConfiguration.lossless
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        
        #expect(decoded.count == pixelData.count)
        for i in 0..<pixelData.count {
            #expect(decoded[i] == pixelData[i], "Mismatch at byte \(i)")
        }
    }
    
    @Test("JPEG-LS near-lossless encode-decode roundtrip")
    func testNearLosslessRoundtrip() throws {
        let codec = JPEGLSCodec()
        let width = 8
        let height = 8
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create test image
        var pixelData = Data(count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixelData[y * width + x] = UInt8((x * 32 + y * 16) % 256)
            }
        }
        
        // Near-lossless with medium quality
        let config = CompressionConfiguration(quality: .medium, preferLossless: false)
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        
        #expect(decoded.count == pixelData.count)
        
        // Verify near-lossless: decoded values should be close to original
        for i in 0..<pixelData.count {
            let diff = abs(Int(decoded[i]) - Int(pixelData[i]))
            // NEAR parameter should limit the max error
            #expect(diff <= 25, "Near-lossless error too large at index \(i): \(diff)")
        }
    }
    
    @Test("JPEG-LS encoded data has valid JPEG-LS structure")
    func testEncodedDataStructure() throws {
        let codec = JPEGLSCodec()
        let width = 4
        let height = 4
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let pixelData = Data(repeating: 100, count: width * height)
        let config = CompressionConfiguration.lossless
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        
        // Verify SOI marker
        #expect(encoded[0] == 0xFF)
        #expect(encoded[1] == 0xD8)
        
        // Verify SOF55 (JPEG-LS frame) marker
        #expect(encoded[2] == 0xFF)
        #expect(encoded[3] == 0xF7)
        
        // Verify EOI marker at end
        #expect(encoded[encoded.count - 2] == 0xFF)
        #expect(encoded[encoded.count - 1] == 0xD9)
    }
    
    @Test("JPEG-LS compression achieves size reduction for compressible data")
    func testCompressionRatio() throws {
        let codec = JPEGLSCodec()
        let width = 64
        let height = 64
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create highly compressible constant image
        let pixelData = Data(repeating: 128, count: width * height)
        let config = CompressionConfiguration.lossless
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        
        // Constant image should compress very well
        #expect(encoded.count < pixelData.count, "JPEG-LS should compress constant image: encoded=\(encoded.count), original=\(pixelData.count)")
    }
    
    @Test("JPEG-LS multi-frame encode via default implementation")
    func testMultiFrameEncode() throws {
        let codec = JPEGLSCodec()
        let width = 4
        let height = 4
        let numFrames = 2
        
        let descriptor = PixelDataDescriptor(
            rows: height, columns: width,
            numberOfFrames: numFrames,
            bitsAllocated: 8, bitsStored: 8, highBit: 7,
            isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create 2-frame test data
        var pixelData = Data(count: width * height * numFrames)
        for i in 0..<pixelData.count {
            pixelData[i] = UInt8(i % 256)
        }
        
        let config = CompressionConfiguration.lossless
        let frames = try codec.encode(pixelData, descriptor: descriptor, configuration: config)
        
        #expect(frames.count == numFrames)
        #expect(frames[0].count > 0)
        #expect(frames[1].count > 0)
    }
}

@Suite("JPEG-LS TransferSyntax Tests")
struct JPEGLSTransferSyntaxTests {
    
    @Test("JPEG-LS Lossless transfer syntax properties")
    func testJPEGLSLossless() {
        let ts = TransferSyntax.jpegLSLossless
        
        #expect(ts.uid == "1.2.840.10008.1.2.4.80")
        #expect(ts.isExplicitVR == true)
        #expect(ts.byteOrder == .littleEndian)
        #expect(ts.isEncapsulated == true)
        #expect(ts.isJPEGLS == true)
        #expect(ts.isLossless == true)
        #expect(ts.isJPEG == false)
        #expect(ts.isJPEG2000 == false)
        #expect(ts.isRLE == false)
    }
    
    @Test("JPEG-LS Near-Lossless transfer syntax properties")
    func testJPEGLSNearLossless() {
        let ts = TransferSyntax.jpegLSNearLossless
        
        #expect(ts.uid == "1.2.840.10008.1.2.4.81")
        #expect(ts.isExplicitVR == true)
        #expect(ts.byteOrder == .littleEndian)
        #expect(ts.isEncapsulated == true)
        #expect(ts.isJPEGLS == true)
        #expect(ts.isLossless == false)
        #expect(ts.isJPEG == false)
        #expect(ts.isJPEG2000 == false)
    }
    
    @Test("TransferSyntax.from returns JPEG-LS types")
    func testFromUIDJPEGLS() {
        let lossless = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.80")
        #expect(lossless?.isJPEGLS == true)
        #expect(lossless?.isLossless == true)
        
        let nearLossless = TransferSyntax.from(uid: "1.2.840.10008.1.2.4.81")
        #expect(nearLossless?.isJPEGLS == true)
        #expect(nearLossless?.isLossless == false)
    }
}

@Suite("JPEG-LS CodecRegistry Tests")
struct JPEGLSCodecRegistryTests {
    
    @Test("CodecRegistry has JPEG-LS codec")
    func testHasJPEGLSCodec() {
        let registry = CodecRegistry.shared
        
        #expect(registry.hasCodec(for: "1.2.840.10008.1.2.4.80") == true)
        #expect(registry.hasCodec(for: "1.2.840.10008.1.2.4.81") == true)
        #expect(registry.codec(for: "1.2.840.10008.1.2.4.80") != nil)
        #expect(registry.codec(for: "1.2.840.10008.1.2.4.81") != nil)
    }
    
    @Test("CodecRegistry has JPEG-LS encoder")
    func testHasJPEGLSEncoder() {
        let registry = CodecRegistry.shared
        
        #expect(registry.hasEncoder(for: "1.2.840.10008.1.2.4.80") == true)
        #expect(registry.hasEncoder(for: "1.2.840.10008.1.2.4.81") == true)
        #expect(registry.encoder(for: "1.2.840.10008.1.2.4.80") != nil)
        #expect(registry.encoder(for: "1.2.840.10008.1.2.4.81") != nil)
    }
    
    @Test("supportedTransferSyntaxes includes JPEG-LS")
    func testSupportedTransferSyntaxesIncludeJPEGLS() {
        let registry = CodecRegistry.shared
        let supported = registry.supportedTransferSyntaxes
        
        #expect(supported.contains("1.2.840.10008.1.2.4.80"))
        #expect(supported.contains("1.2.840.10008.1.2.4.81"))
    }
    
    @Test("supportedEncodingTransferSyntaxes includes JPEG-LS")
    func testSupportedEncodingTransferSyntaxesIncludeJPEGLS() {
        let registry = CodecRegistry.shared
        let supported = registry.supportedEncodingTransferSyntaxes
        
        #expect(supported.contains("1.2.840.10008.1.2.4.80"))
        #expect(supported.contains("1.2.840.10008.1.2.4.81"))
    }
}

// NOTE: The "JPEG-LS Preset Parameters Tests" suite was removed when the
// in-tree JPEG-LS implementation (and its internal JPEGLSPresetParameters
// type) was retired in favour of the JLSwift `JPEGLS` package. Preset-parameter
// behaviour is now owned and tested by JLSwift; DICOMCore validates JPEG-LS only
// through the public JPEGLSCodec encode/decode round-trips above.


@Suite("JPEGLSCodec strict frame decoding")
struct JPEGLSCodecStrictDecodingTests {
    private static let lossless = TransferSyntax.jpegLSLossless.uid
    private static let nearLossless = TransferSyntax.jpegLSNearLossless.uid

    private func descriptor(
        rows: Int, columns: Int, bitsAllocated: Int = 8, bitsStored: Int = 8, samples: Int = 1
    ) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows, columns: columns, bitsAllocated: bitsAllocated, bitsStored: bitsStored,
            highBit: bitsStored - 1, isSigned: false, samplesPerPixel: samples,
            photometricInterpretation: samples == 3 ? .rgb : .monochrome2)
    }

    private func frame(_ descriptor: PixelDataDescriptor) -> Data {
        let count = descriptor.rows * descriptor.columns * descriptor.samplesPerPixel
        if descriptor.bitsAllocated == 8 {
            return Data((0..<count).map { UInt8(($0 * 37 + 11) % 256) })
        }
        let maximum = (1 << descriptor.bitsStored) - 1
        var bytes = Data(capacity: count * 2)
        for index in 0..<count {
            let value = UInt16((index * 611 + 5) % (maximum + 1))
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8(value >> 8))
        }
        return bytes
    }

    private func encode(_ descriptor: PixelDataDescriptor, configuration: CompressionConfiguration = .lossless) throws -> (Data, Data) {
        let original = frame(descriptor)
        let encoded = try JPEGLSCodec().encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: configuration)
        return (original, encoded)
    }

    /// NEAR of the first scan: SOS = FFDA Ls Ns (Ci Tmi)×Ns NEAR ILV Ah/Al.
    private func near(of stream: Data) -> Int? {
        let bytes = [UInt8](stream)
        guard let sos = (0..<(bytes.count - 1)).first(where: { bytes[$0] == 0xFF && bytes[$0 + 1] == 0xDA }) else { return nil }
        let ns = Int(bytes[sos + 4])
        return Int(bytes[sos + 5 + 2 * ns])
    }

    @Test("An exact lossless frame decodes byte-identically under every decoder instance")
    func exactFrame() throws {
        let descriptor = descriptor(rows: 5, columns: 7)
        let (original, encoded) = try encode(descriptor)
        for codec in [JPEGLSCodec(), JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless), JPEGLSCodec(decodingTransferSyntaxUID: Self.nearLossless)] {
            #expect(try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0) == original)
        }
    }

    @Test("Dimension mismatches throw instead of zero-filling or truncating")
    func dimensionMismatch() throws {
        let (_, encoded) = try encode(descriptor(rows: 4, columns: 4))
        for (rows, columns) in [(4, 3), (3, 4), (2, 8), (8, 8), (4, 5), (1, 16)] {
            #expect(throws: DICOMError.self, "\(columns)x\(rows)") {
                try JPEGLSCodec().decodeFrame(encoded, descriptor: descriptor(rows: rows, columns: columns), frameIndex: 0)
            }
        }
    }

    @Test("Component count mismatches throw")
    func componentMismatch() throws {
        let gray = descriptor(rows: 4, columns: 4)
        let rgb = descriptor(rows: 4, columns: 4, samples: 3)
        let (_, grayEncoded) = try encode(gray)
        let (_, rgbEncoded) = try encode(rgb)
        #expect(throws: DICOMError.self) { try JPEGLSCodec().decodeFrame(rgbEncoded, descriptor: gray, frameIndex: 0) }
        #expect(throws: DICOMError.self) { try JPEGLSCodec().decodeFrame(grayEncoded, descriptor: rgb, frameIndex: 0) }
    }

    @Test("Precision differing from Bits Stored throws instead of clamping or widening")
    func precisionMismatch() throws {
        let wide = descriptor(rows: 4, columns: 4, bitsAllocated: 16, bitsStored: 12)
        let (original, encoded) = try encode(wide)
        #expect(try JPEGLSCodec().decodeFrame(encoded, descriptor: wide, frameIndex: 0) == original)
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec().decodeFrame(encoded, descriptor: descriptor(rows: 4, columns: 4), frameIndex: 0)
        }
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec().decodeFrame(encoded, descriptor: descriptor(rows: 4, columns: 4, bitsAllocated: 16, bitsStored: 16), frameIndex: 0)
        }
        // An 8-bit scan under Bits Stored 16 is a header/bitstream mismatch (DCMTK refuses it too).
        let narrow = descriptor(rows: 4, columns: 4)
        let (narrowOriginal, narrowEncoded) = try encode(narrow)
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec().decodeFrame(narrowEncoded, descriptor: descriptor(rows: 4, columns: 4, bitsAllocated: 16, bitsStored: 16), frameIndex: 0)
        }
        // With Bits Stored 8 in a 16-bit container the samples widen exactly.
        let widened = try JPEGLSCodec().decodeFrame(
            narrowEncoded, descriptor: descriptor(rows: 4, columns: 4, bitsAllocated: 16, bitsStored: 8), frameIndex: 0)
        #expect(widened.count == narrowOriginal.count * 2)
        #expect(stride(from: 0, to: widened.count, by: 2).map { widened[$0] } == [UInt8](narrowOriginal))
        #expect(stride(from: 1, to: widened.count, by: 2).allSatisfy { widened[$0] == 0 })
    }

    @Test("Near-lossless scans are refused under the lossless syntax only")
    func nearLosslessScan() throws {
        let descriptor = descriptor(rows: 8, columns: 8)
        let lossy = CompressionConfiguration(quality: .low, speed: .balanced, progressive: false, preferLossless: false)
        let (_, encoded) = try encode(descriptor, configuration: lossy)
        let (_, exact) = try encode(descriptor)
        try #require(near(of: encoded) ?? 0 > 0)
        try #require(near(of: exact) == 0)

        #expect(throws: DICOMError.self) {
            try JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless).decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        }
        #expect(try JPEGLSCodec(decodingTransferSyntaxUID: Self.nearLossless).decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 64)
        #expect(try JPEGLSCodec().decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 64)
        #expect(try JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless).decodeFrame(exact, descriptor: descriptor, frameIndex: 0).count == 64)

        let registry = CodecRegistry.shared
        let losslessCodec = try #require(registry.codec(for: Self.lossless))
        let nearCodec = try #require(registry.codec(for: Self.nearLossless))
        #expect(throws: DICOMError.self) { try losslessCodec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0) }
        #expect(try nearCodec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 64)
    }

    @Test("A CharLS stream with a fill byte before EOI decodes (JLSwift 0.9.2)")
    func charLSFillByteBeforeEOI() throws {
        // 1x3 8-bit lossless [0, 1, 255] as written by DCMTK 3.7.0 dcmcjpls: the
        // entropy data `AA 00` is followed by a legal 0xFF fill byte, then EOI.
        let stream = Data([
            0xFF, 0xD8, 0xFF, 0xF7, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x03, 0x01, 0x01, 0x11, 0x00,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0xAA, 0x00, 0xFF, 0xFF, 0xD9,
        ])
        let descriptor = descriptor(rows: 1, columns: 3)
        #expect(try JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless).decodeFrame(stream, descriptor: descriptor, frameIndex: 0) == Data([0, 1, 255]))
    }

    @Test("Truncated and empty streams throw")
    func malformed() throws {
        let descriptor = descriptor(rows: 4, columns: 4)
        let (_, encoded) = try encode(descriptor)
        #expect(throws: DICOMError.self) { try JPEGLSCodec().decodeFrame(Data(), descriptor: descriptor, frameIndex: 0) }
        #expect(throws: DICOMError.self) { try JPEGLSCodec().decodeFrame(encoded.prefix(encoded.count / 2), descriptor: descriptor, frameIndex: 0) }
        #expect(throws: DICOMError.self) {
            try JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless).decodeFrame(Data([0, 1, 2, 3]), descriptor: descriptor, frameIndex: 0)
        }
    }

    // MARK: - Legacy DICOMKIT_0.5.0 Unclamped MAXVAL (> 12-bit, Missing LSE) Recovery

    /// Synthesizes a genuine legacy JPEG-LS codestream matching `DICOMKIT_0.5.0`'s defect:
    /// encodes with unclamped ITU-T T.87 Table C.2 thresholds (`factor = (MAXVAL + 128) / 256`,
    /// e.g. `T1=258, T2=1027, T3=4356` for 16-bit lossless) and strips the 15-byte `LSE` (`FF F8`)
    /// preset segment so the stream carries no `LSE` marker before `SOS`.
    static func makeLegacyUnclampedCodestream(
        pixels: Data,
        width: Int,
        height: Int,
        bitsPerSample: Int,
        samplesPerPixel: Int = 1,
        near: Int = 0
    ) async throws -> Data {
        let maxVal = (1 << bitsPerSample) - 1
        let factor = (maxVal + 128) / 256
        let t1 = min(max(factor * (3 - 2) + 2 + 3 * near, near + 1), maxVal)
        let t2 = min(max(factor * (7 - 3) + 3 + 5 * near, t1), maxVal)
        let t3 = min(max(factor * (21 - 4) + 4 + 7 * near, t2), maxVal)
        let preset = try SwiftJLS.CodecOptions.Preset(
            maximumSampleValue: maxVal,
            threshold1: t1,
            threshold2: t2,
            threshold3: t3,
            reset: 64
        )
        let limits = try SwiftJLS.ResourceLimits(
            maximumCompressedBytes: 16 << 20,
            maximumDecodedBytes: 16 << 20,
            maximumWorkspaceBytes: 64 << 20,
            maximumPixels: 4 << 20,
            deadlineSeconds: 30.0,
            maximumMemoryBytes: Int.max
        )
        let components: [SwiftJLS.ComponentRole]
        let colour: SwiftJLS.ColourInterpretation
        let planes: [SwiftJLS.PlaneDescriptor]
        let interleave: SwiftJLS.CodecOptions.InterleaveMode
        if samplesPerPixel == 1 {
            components = [.grey]
            colour = .greyscale
            planes = [
                try SwiftJLS.PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [0],
                    offset: 0,
                    sampleStride: 2,
                    pixelStride: 2,
                    rowBytes: width * 2,
                    byteCount: width * height * 2
                )
            ]
            interleave = .none
        } else {
            components = [
                .uninterpreted("JPEG-LS:1"),
                .uninterpreted("JPEG-LS:2"),
                .uninterpreted("JPEG-LS:3")
            ]
            colour = .unknown
            planes = [
                try SwiftJLS.PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [0, 1, 2],
                    offset: 0,
                    sampleStride: 2,
                    pixelStride: 6,
                    rowBytes: width * 6,
                    byteCount: width * height * 6
                )
            ]
            interleave = .sample
        }
        let imgDesc = try SwiftJLS.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: 16,
            meaningfulBits: bitsPerSample,
            byteOrder: .littleEndian,
            components: components,
            colour: colour,
            alpha: .absent,
            planes: planes,
            limits: limits
        )
        let dest = try SwiftJLS.ImageDestination.allocate(descriptor: imgDesc, limits: limits)
        let image = try dest.write { dst in
            pixels.withUnsafeBytes { src in
                dst.copyMemory(from: src)
            }
        }
        let mode: SwiftJLS.CompressionMode = near == 0 ? .lossless : .nearLossless(maximumAbsoluteError: near)
        let options = try SwiftJLS.CodecOptions(
            restartIntervalLines: 0,
            preset: preset,
            interleaveMode: interleave,
            colourTransform: .none
        )
        let encoder = try SwiftJLS.Encoder(configuration: .init(mode: mode, codecOptions: options))
        let encoded = try await encoder.encode(
            image,
            options: .init(resourceLimits: limits, copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        ).data

        let expectedLSE = Data([
            0xFF, 0xF8, 0x00, 0x0D, 0x01,
            UInt8((maxVal >> 8) & 0xFF), UInt8(maxVal & 0xFF),
            UInt8((t1 >> 8) & 0xFF), UInt8(t1 & 0xFF),
            UInt8((t2 >> 8) & 0xFF), UInt8(t2 & 0xFF),
            UInt8((t3 >> 8) & 0xFF), UInt8(t3 & 0xFF),
            0x00, 0x40
        ])
        let range = try #require(encoded.range(of: expectedLSE))
        var stripped = Data()
        stripped.append(encoded[..<range.lowerBound])
        stripped.append(encoded[range.upperBound...])
        return stripped
    }

    @Test("Legacy 13..16-bit unclamped-MAXVAL JPEG-LS streams without LSE recover bit-exactly")
    func legacyUnclampedMaxValRecoveryAcrossPrecisions() async throws {
        let width = 32
        let height = 32
        for bits in 13...16 {
            let maxVal = (1 << bits) - 1
            let isSigned = (bits == 16)
            var pixels = Data(capacity: width * height * 2)
            for y in 0..<height {
                for x in 0..<width {
                    // Use sharp local steps across 18..4356 so context quantization differs
                    // decisively between standard Table C.2 (T1=18,T2=67,T3=276) and legacy unclamped.
                    let raw: Int
                    if (x + y) % 5 == 0 {
                        raw = (x * 997 + y * 4099) & maxVal
                    } else {
                        raw = ((x * 73 + y * 211) + ((y % 3) * 1800)) & maxVal
                    }
                    let word = UInt16(raw)
                    pixels.append(UInt8(word & 0xFF))
                    pixels.append(UInt8((word >> 8) & 0xFF))
                }
            }
            let legacyStream = try await Self.makeLegacyUnclampedCodestream(
                pixels: pixels,
                width: width,
                height: height,
                bitsPerSample: bits
            )
            // Confirm no LSE marker remains in the stripped legacy codestream.
            #expect(legacyStream.range(of: Data([0xFF, 0xF8, 0x00, 0x0D, 0x01])) == nil)

            let desc = PixelDataDescriptor(
                rows: height,
                columns: width,
                bitsAllocated: 16,
                bitsStored: bits,
                highBit: bits - 1,
                isSigned: isSigned,
                samplesPerPixel: 1,
                photometricInterpretation: .monochrome2
            )
            let codec = JPEGLSCodec(decodingTransferSyntaxUID: Self.lossless)
            let decoded = try codec.decodeFrame(legacyStream, descriptor: desc, frameIndex: 0)
            #expect(decoded == pixels, "Bit-exact recovery failed for \(bits)-bit monochrome")

            // Exact encoded byte ceiling must still admit the 15-byte internal LSE synthesis.
            let tightLimits = PixelDecodeLimits(
                maximumEncodedBytes: legacyStream.count,
                maximumDecodedBytes: 4 << 20,
                maximumPixels: width * height
            )
            let tightCodec = JPEGLSCodec(decodingSyntax: .lossless, decodingLimits: tightLimits)
            let tightDecoded = try tightCodec.decodePixelFrame(legacyStream, descriptor: desc, frameIndex: 0)
            #expect(tightDecoded.data == pixels)
        }
    }

    @Test("Legacy 16-bit unclamped-MAXVAL DICOM fragments with odd codestream + 0x00 even-padding recover bit-exactly")
    func legacyUnclampedMaxValRecoveryBothParitiesAndDICOMPadding() async throws {
        let width = 32
        let height = 32
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )

        var foundOddRaw: (pixels: Data, raw: Data)?
        var foundEvenRaw: (pixels: Data, raw: Data)?
        for seed in 0..<32 where foundOddRaw == nil || foundEvenRaw == nil {
            var pixels = Data(capacity: width * height * 2)
            for i in 0..<(width * height) {
                let v = Int16(truncatingIfNeeded: -1024 + ((i * (313 + seed * 17) + seed * 97) % 4500))
                let word = UInt16(bitPattern: v)
                pixels.append(UInt8(word & 0xFF))
                pixels.append(UInt8((word >> 8) & 0xFF))
            }
            let raw = try await Self.makeLegacyUnclampedCodestream(
                pixels: pixels,
                width: width,
                height: height,
                bitsPerSample: 16
            )
            if raw.count % 2 == 1, foundOddRaw == nil {
                foundOddRaw = (pixels, raw)
            } else if raw.count % 2 == 0, foundEvenRaw == nil {
                foundEvenRaw = (pixels, raw)
            }
        }

        let oddCase = try #require(foundOddRaw, "Expected at least one odd-length legacy 16-bit codestream")
        let evenCase = try #require(foundEvenRaw, "Expected at least one even-length legacy 16-bit codestream")

        // DICOM PS3.5 Section 8.2 pads odd-length encapsulated fragments with a single 0x00 byte.
        var dicomPaddedOdd = oddCase.raw
        dicomPaddedOdd.append(0x00)
        #expect(dicomPaddedOdd.count % 2 == 0)
        #expect(Array(dicomPaddedOdd.suffix(3)) == [0xFF, 0xD9, 0x00])

        let codec = JPEGLSCodec(decodingSyntax: .lossless)
        #expect(try codec.decodeFrame(oddCase.raw, descriptor: desc, frameIndex: 0) == oddCase.pixels)
        #expect(try codec.decodeFrame(dicomPaddedOdd, descriptor: desc, frameIndex: 0) == oddCase.pixels)
        #expect(try codec.decodeFrame(evenCase.raw, descriptor: desc, frameIndex: 0) == evenCase.pixels)

        // Managed path must also recover the DICOM 0x00-padded fragment with zero retained staging.
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let inBuf = try DICOMByteBuffer(count: dicomPaddedOdd.count, budget: budget, resource: .encoded)
            dicomPaddedOdd.withUnsafeBytes { inBuf.unsafeMutableBytes.copyMemory(from: $0) }
            let managed = try codec.decodeManagedPixelFrame(inBuf, descriptor: desc, frameIndex: 0, budget: budget)
            #expect(managed.data.withUnsafeBytes { Data($0) } == oddCase.pixels)
            #expect(budget.receipt.current.staging == 0)
        }
        #expect(budget.receipt.currentTotal == baseline)

        // Illegal 0x00 pad on an already even-length codestream (making odd total) and double 0x00 pad must still fail.
        var illegalEvenPlusZero = evenCase.raw
        illegalEvenPlusZero.append(0x00)
        #expect(throws: DICOMError.self) {
            _ = try codec.decodeFrame(illegalEvenPlusZero, descriptor: desc, frameIndex: 0)
        }
        var illegalDoubleZero = evenCase.raw
        illegalDoubleZero.append(contentsOf: [0x00, 0x00])
        #expect(throws: DICOMError.self) {
            _ = try codec.decodeFrame(illegalDoubleZero, descriptor: desc, frameIndex: 0)
        }
    }

    @Test("Legacy 16-bit 3-component unclamped-MAXVAL JPEG-LS stream without LSE recovers bit-exactly")
    func legacyUnclampedMaxValRecoveryRGB16() async throws {
        let width = 16
        let height = 16
        var pixels = Data(capacity: width * height * 6)
        for i in 0..<(width * height * 3) {
            let word = UInt16((i * 2503 + (i % 7) * 911) & 0xFFFF)
            pixels.append(UInt8(word & 0xFF))
            pixels.append(UInt8((word >> 8) & 0xFF))
        }
        let legacyStream = try await Self.makeLegacyUnclampedCodestream(
            pixels: pixels,
            width: width,
            height: height,
            bitsPerSample: 16,
            samplesPerPixel: 3
        )
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
        let decoded = try JPEGLSCodec(decodingSyntax: .lossless)
            .decodeFrame(legacyStream, descriptor: desc, frameIndex: 0)
        #expect(decoded == pixels)

        let budget = try DICOMAllocationBudget()
        let inBuf = try DICOMByteBuffer(count: legacyStream.count, budget: budget, resource: .encoded)
        legacyStream.withUnsafeBytes { inBuf.unsafeMutableBytes.copyMemory(from: $0) }
        let managed = try JPEGLSCodec(decodingSyntax: .lossless)
            .decodeManagedPixelFrame(inBuf, descriptor: desc, frameIndex: 0, budget: budget)
        #expect(managed.data.withUnsafeBytes { Data($0) } == pixels)
        #expect(budget.receipt.current.staging == 0)
    }

    @Test("JPEGLSCodec 16-bit encoder emits standard ITU-T T.87 Table C.2 clamped thresholds")
    func sixteenBitEncoderUsesClampedTableC2Defaults() async throws {
        let width = 24
        let height = 24
        var pixels = Data(capacity: width * height * 2)
        for i in 0..<(width * height) {
            let signedCT = Int16(truncatingIfNeeded: -1024 + ((i * 317) % 3500))
            let word = UInt16(bitPattern: signedCT)
            pixels.append(UInt8(word & 0xFF))
            pixels.append(UInt8((word >> 8) & 0xFF))
        }
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: true,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let encoded = try JPEGLSCodec().encodeFrame(pixels, descriptor: desc, frameIndex: 0, configuration: .lossless)
        // Decode directly with unmodified SwiftJLS.Decoder to prove standard Table C.2 compliance.
        let limits = try SwiftJLS.ResourceLimits(
            maximumCompressedBytes: 4 << 20,
            maximumDecodedBytes: 4 << 20,
            maximumWorkspaceBytes: 16 << 20,
            maximumPixels: width * height,
            deadlineSeconds: 10.0,
            maximumMemoryBytes: Int.max
        )
        let decoder = try SwiftJLS.Decoder(configuration: .init(codecOptions: .init()))
        let imgDesc = try SwiftJLS.ImageDescriptor(
            width: width,
            height: height,
            sampleType: .unsignedInteger,
            storageBits: 16,
            meaningfulBits: 16,
            byteOrder: .littleEndian,
            components: [.grey],
            colour: .greyscale,
            alpha: .absent,
            planes: [
                try SwiftJLS.PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [0],
                    offset: 0,
                    sampleStride: 2,
                    pixelStride: 2,
                    rowBytes: width * 2,
                    byteCount: width * height * 2
                )
            ],
            limits: limits
        )
        let dest = try SwiftJLS.ImageDestination.allocate(descriptor: imgDesc, limits: limits)
        let direct = try await decoder.decode(
            encoded,
            into: dest,
            options: .init(resourceLimits: limits, copyPolicy: .requireSharedStorage, metadataPolicy: .discardAncillary)
        )
        let directBytes = try direct.image.storage.withUnsafeBytes { Data($0) }
        #expect(directBytes == pixels)
    }

    @Test("Streams with explicit LSE Id=1 or genuine 16-bit corruption are never mis-recovered")
    func explicitLSEAndCorrupt16BitStreamsStillFail() async throws {
        let width = 16
        let height = 16
        var pixels = Data(capacity: width * height * 2)
        for i in 0..<(width * height) {
            let word = UInt16((i * 1777) & 0xFFFF)
            pixels.append(UInt8(word & 0xFF))
            pixels.append(UInt8((word >> 8) & 0xFF))
        }
        let desc = PixelDataDescriptor(
            rows: height,
            columns: width,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let valid = try JPEGLSCodec().encodeFrame(pixels, descriptor: desc, frameIndex: 0, configuration: .lossless)
        // Truncate inside entropy data while preserving EOI so header inspection passes but entropy fails.
        var truncatedEntropy = Data(valid.prefix(max(24, valid.count / 2)))
        truncatedEntropy.append(contentsOf: [0xFF, 0xD9])
        #expect(throws: DICOMError.self) {
            _ = try JPEGLSCodec(decodingSyntax: .lossless).decodeFrame(truncatedEntropy, descriptor: desc, frameIndex: 0)
        }

        // Inject an explicit standard LSE Id=1 before SOS in a legacy unclamped stream:
        // decoder must honour the explicit LSE and reject rather than overwriting it.
        let legacyStream = try await Self.makeLegacyUnclampedCodestream(
            pixels: pixels,
            width: width,
            height: height,
            bitsPerSample: 16
        )
        let sosMarker = try #require(legacyStream.range(of: Data([0xFF, 0xDA])))
        var mismatchedExplicitLSE = Data()
        mismatchedExplicitLSE.append(legacyStream[..<sosMarker.lowerBound])
        // Explicit LSE Id=1 declaring standard T1=18 (0x0012), T2=67 (0x0043), T3=276 (0x0114)
        mismatchedExplicitLSE.append(contentsOf: [
            0xFF, 0xF8, 0x00, 0x0D, 0x01,
            0xFF, 0xFF, 0x00, 0x12, 0x00, 0x43, 0x01, 0x14, 0x00, 0x40
        ])
        mismatchedExplicitLSE.append(legacyStream[sosMarker.lowerBound...])
        #expect(throws: DICOMError.self) {
            _ = try JPEGLSCodec(decodingSyntax: .lossless)
                .decodeFrame(mismatchedExplicitLSE, descriptor: desc, frameIndex: 0)
        }
    }
}
