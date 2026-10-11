import Testing
import Foundation
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
}
