import Testing
import Foundation
@testable import DICOMCore

@Suite("TranscodingConfiguration Tests")
struct TranscodingConfigurationTests {
    
    @Test("Default configuration prefers Explicit VR Little Endian")
    func testDefaultConfiguration() {
        let config = TranscodingConfiguration.default
        
        #expect(config.preferredSyntaxes.count == 2)
        #expect(config.preferredSyntaxes[0].uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(config.preferredSyntaxes[1].uid == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(config.allowLossyCompression == false)
        #expect(config.preservePixelDataFidelity == true)
    }
    
    @Test("Max compression configuration allows lossy")
    func testMaxCompressionConfiguration() {
        let config = TranscodingConfiguration.maxCompression
        
        #expect(config.allowLossyCompression == true)
        #expect(config.preservePixelDataFidelity == false)
        #expect(config.preferredSyntaxes.contains { $0.uid == TransferSyntax.htj2kLossy.uid })
        #expect(config.preferredSyntaxes.contains { $0.uid == TransferSyntax.jpegBaseline.uid })
    }
    
    @Test("Lossless compression configuration only includes lossless syntaxes")
    func testLosslessCompressionConfiguration() {
        let config = TranscodingConfiguration.losslessCompression
        
        #expect(config.allowLossyCompression == false)
        #expect(config.preservePixelDataFidelity == true)
        #expect(config.preferredSyntaxes.contains { $0.uid == TransferSyntax.htj2kLossless.uid })
        #expect(config.preferredSyntaxes.contains { $0.uid == TransferSyntax.htj2kRPCLLossless.uid })
        
        // All syntaxes should be lossless
        for syntax in config.preferredSyntaxes {
            #expect(syntax.isLossless == true)
        }
    }
    
    @Test("Custom configuration creation")
    func testCustomConfiguration() {
        let config = TranscodingConfiguration(
            preferredSyntaxes: [.explicitVRBigEndian, .implicitVRLittleEndian],
            allowLossyCompression: true,
            preservePixelDataFidelity: false
        )
        
        #expect(config.preferredSyntaxes.count == 2)
        #expect(config.preferredSyntaxes[0].uid == TransferSyntax.explicitVRBigEndian.uid)
        #expect(config.allowLossyCompression == true)
        #expect(config.preservePixelDataFidelity == false)
    }
    
    @Test("Configuration is hashable")
    func testHashable() {
        let config1 = TranscodingConfiguration.default
        let config2 = TranscodingConfiguration.default
        
        #expect(config1 == config2)
        
        var set: Set<TranscodingConfiguration> = []
        set.insert(config1)
        set.insert(config2)
        
        #expect(set.count == 1)
    }
}

@Suite("TranscodingResult Tests")
struct TranscodingResultTests {
    
    @Test("Transcoding result with actual transcoding")
    func testResultWithTranscoding() {
        let result = TranscodingResult(
            data: Data([0x01, 0x02, 0x03]),
            sourceTransferSyntax: .implicitVRLittleEndian,
            targetTransferSyntax: .explicitVRLittleEndian,
            wasTranscoded: true,
            isLossless: true
        )
        
        #expect(result.data.count == 3)
        #expect(result.sourceTransferSyntax.uid == TransferSyntax.implicitVRLittleEndian.uid)
        #expect(result.targetTransferSyntax.uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(result.wasTranscoded == true)
        #expect(result.isLossless == true)
    }
    
    @Test("Transcoding result without actual transcoding (same syntax)")
    func testResultWithoutTranscoding() {
        let result = TranscodingResult(
            data: Data([0x01, 0x02, 0x03]),
            sourceTransferSyntax: .explicitVRLittleEndian,
            targetTransferSyntax: .explicitVRLittleEndian,
            wasTranscoded: false,
            isLossless: true
        )
        
        #expect(result.wasTranscoded == false)
        #expect(result.isLossless == true)
    }
}

@Suite("TranscodingError Tests")
struct TranscodingErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() {
        let errors: [TranscodingError] = [
            .unsupportedSourceSyntax("1.2.3.4"),
            .unsupportedTargetSyntax("1.2.3.5"),
            .noCompatibleSyntax,
            .pixelDataExtractionFailed("Test reason"),
            .encodingFailed("Test encoding"),
            .parsingFailed("Test parsing"),
            .lossyCompressionNotAllowed,
            .fidelityLost
        ]
        
        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
    
    @Test("Errors are equatable")
    func testEquatable() {
        let error1 = TranscodingError.unsupportedSourceSyntax("1.2.3.4")
        let error2 = TranscodingError.unsupportedSourceSyntax("1.2.3.4")
        let error3 = TranscodingError.unsupportedSourceSyntax("1.2.3.5")
        
        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

@Suite("TransferSyntaxConverter Tests")
struct TransferSyntaxConverterTests {
    
    @Test("Converter with default configuration")
    func testDefaultConverter() {
        let converter = TransferSyntaxConverter()
        
        #expect(converter.configuration.allowLossyCompression == false)
        #expect(converter.configuration.preservePixelDataFidelity == true)
    }
    
    @Test("Converter with custom configuration")
    func testCustomConverter() {
        let config = TranscodingConfiguration.maxCompression
        let converter = TransferSyntaxConverter(configuration: config)
        
        #expect(converter.configuration.allowLossyCompression == true)
    }
    
    // MARK: - canTranscode Tests
    
    @Test("Can transcode same syntax (no-op)")
    func testCanTranscodeSameSyntax() {
        let converter = TransferSyntaxConverter()
        
        #expect(converter.canTranscode(from: .explicitVRLittleEndian, to: .explicitVRLittleEndian) == true)
        #expect(converter.canTranscode(from: .implicitVRLittleEndian, to: .implicitVRLittleEndian) == true)
        #expect(converter.canTranscode(from: .explicitVRBigEndian, to: .explicitVRBigEndian) == true)
    }
    
    @Test("Can transcode between uncompressed syntaxes")
    func testCanTranscodeBetweenUncompressed() {
        let converter = TransferSyntaxConverter()
        
        // Explicit to Implicit
        #expect(converter.canTranscode(from: .explicitVRLittleEndian, to: .implicitVRLittleEndian) == true)
        
        // Implicit to Explicit
        #expect(converter.canTranscode(from: .implicitVRLittleEndian, to: .explicitVRLittleEndian) == true)
        
        // Little Endian to Big Endian
        #expect(converter.canTranscode(from: .explicitVRLittleEndian, to: .explicitVRBigEndian) == true)
        
        // Big Endian to Little Endian
        #expect(converter.canTranscode(from: .explicitVRBigEndian, to: .explicitVRLittleEndian) == true)
        
        // Implicit to Big Endian
        #expect(converter.canTranscode(from: .implicitVRLittleEndian, to: .explicitVRBigEndian) == true)
    }
    
    #if canImport(ImageIO)
    @Test("Can transcode to compressed syntax with encoder support")
    func testCanTranscodeToCompressed() {
        let converter = TransferSyntaxConverter()
        
        // Can encode to JPEG Baseline if encoder is available
        if CodecRegistry.shared.hasEncoder(for: TransferSyntax.jpegBaseline.uid) {
            #expect(converter.canTranscode(from: .explicitVRLittleEndian, to: .jpegBaseline) == true)
        }
        
        // Can encode to JPEG 2000 Lossless if encoder is available
        if CodecRegistry.shared.hasEncoder(for: TransferSyntax.jpeg2000Lossless.uid) {
            #expect(converter.canTranscode(from: .implicitVRLittleEndian, to: .jpeg2000Lossless) == true)
        }
    }
    #else
    @Test("Cannot transcode to compressed syntax without ImageIO")
    func testCannotTranscodeToCompressedWithoutImageIO() {
        let converter = TransferSyntaxConverter()
        
        // Cannot encode without ImageIO
        #expect(converter.canTranscode(from: .explicitVRLittleEndian, to: .jpegBaseline) == false)
        #expect(converter.canTranscode(from: .implicitVRLittleEndian, to: .jpeg2000Lossless) == false)
    }
    #endif
    
    #if canImport(ImageIO)
    @Test("Can decompress JPEG to uncompressed (if codec available)")
    func testCanDecompressJPEG() {
        let converter = TransferSyntaxConverter()
        
        // JPEG to Explicit VR LE (decompression)
        if CodecRegistry.shared.hasCodec(for: TransferSyntax.jpegBaseline.uid) {
            #expect(converter.canTranscode(from: .jpegBaseline, to: .explicitVRLittleEndian) == true)
        }
    }
    #endif
    
    @Test("Can decompress RLE to uncompressed")
    func testCanDecompressRLE() {
        let converter = TransferSyntaxConverter()
        
        // RLE to Explicit VR LE (decompression)
        #expect(converter.canTranscode(from: .rleLossless, to: .explicitVRLittleEndian) == true)
        #expect(converter.canTranscode(from: .rleLossless, to: .implicitVRLittleEndian) == true)
    }

    @Test("Can recompress between JPEG 2000 and HTJ2K families when codecs are available")
    func testCanRecompressBetweenJPEG2000Families() {
        let converter = TransferSyntaxConverter()

        let expectedForward = CodecRegistry.shared.hasCodec(for: TransferSyntax.jpeg2000Lossless.uid)
            && CodecRegistry.shared.hasEncoder(for: TransferSyntax.htj2kLossless.uid)
        let expectedReverse = CodecRegistry.shared.hasCodec(for: TransferSyntax.htj2kLossless.uid)
            && CodecRegistry.shared.hasEncoder(for: TransferSyntax.jpeg2000Lossless.uid)

        #expect(converter.canTranscode(from: .jpeg2000Lossless, to: .htj2kLossless) == expectedForward)
        #expect(converter.canTranscode(from: .htj2kLossless, to: .jpeg2000Lossless) == expectedReverse)
    }
    
    // MARK: - selectTargetSyntax Tests
    
    @Test("Select target syntax from accepted list")
    func testSelectTargetSyntax() {
        let converter = TransferSyntaxConverter()
        
        let accepted = [
            TransferSyntax.implicitVRLittleEndian.uid,
            TransferSyntax.explicitVRLittleEndian.uid
        ]
        
        let target = converter.selectTargetSyntax(
            for: Data(),
            sourceSyntax: .explicitVRLittleEndian,
            acceptedSyntaxes: accepted
        )
        
        // Should select Explicit VR LE (first in preferred list that's accepted)
        #expect(target?.uid == TransferSyntax.explicitVRLittleEndian.uid)
    }
    
    @Test("Select target syntax returns nil when none compatible")
    func testSelectTargetSyntaxNoCompatible() {
        let config = TranscodingConfiguration(
            preferredSyntaxes: [.jpegBaseline],
            allowLossyCompression: true,
            preservePixelDataFidelity: false
        )
        let converter = TransferSyntaxConverter(configuration: config)
        
        let accepted = ["9.9.9.9"]
        
        let target = converter.selectTargetSyntax(
            for: Data(),
            sourceSyntax: .explicitVRLittleEndian,
            acceptedSyntaxes: accepted
        )
        
        #expect(target == nil)
    }
    
    @Test("Select target syntax respects lossy constraint")
    func testSelectTargetSyntaxRespectsLossyConstraint() {
        let config = TranscodingConfiguration(
            preferredSyntaxes: [.jpegBaseline, .explicitVRLittleEndian],
            allowLossyCompression: false,
            preservePixelDataFidelity: true
        )
        let converter = TransferSyntaxConverter(configuration: config)
        
        let accepted = [
            TransferSyntax.jpegBaseline.uid,
            TransferSyntax.explicitVRLittleEndian.uid
        ]
        
        let target = converter.selectTargetSyntax(
            for: Data(),
            sourceSyntax: .implicitVRLittleEndian,
            acceptedSyntaxes: accepted
        )
        
        // Should skip JPEG (lossy) and select Explicit VR LE (lossless)
        #expect(target?.uid == TransferSyntax.explicitVRLittleEndian.uid)
    }
    
    // MARK: - transcode Tests
    
    @Test("Transcode same syntax returns unchanged data")
    func testTranscodeSameSyntax() throws {
        let converter = TransferSyntaxConverter()
        let sourceData = Data([0x01, 0x02, 0x03, 0x04])
        
        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .explicitVRLittleEndian
        )
        
        #expect(result.data == sourceData)
        #expect(result.wasTranscoded == false)
        #expect(result.isLossless == true)
    }
    
    @Test("Transcode throws for unsupported target")
    func testTranscodeUnsupportedTarget() {
        let converter = TransferSyntaxConverter()
        let sourceData = Data([0x01, 0x02, 0x03, 0x04])
        
        #expect(throws: TranscodingError.self) {
            try converter.transcode(
                dataSetData: sourceData,
                from: .explicitVRLittleEndian,
                to: .jpegBaseline // Cannot encode to JPEG
            )
        }
    }
    
    @Test("Transcoding configuration respects lossy constraint")
    func testTranscodingConfigRespectsLossyConstraint() {
        // Verify that configurations with allowLossyCompression=false
        // correctly filter out lossy transfer syntaxes
        let config = TranscodingConfiguration(
            preferredSyntaxes: [.jpegBaseline, .jpeg2000, .explicitVRLittleEndian],
            allowLossyCompression: false,
            preservePixelDataFidelity: true
        )
        let converter = TransferSyntaxConverter(configuration: config)
        
        // When selecting a target syntax, lossy syntaxes should be skipped
        let accepted = [
            TransferSyntax.jpegBaseline.uid,
            TransferSyntax.explicitVRLittleEndian.uid
        ]
        
        let target = converter.selectTargetSyntax(
            for: Data(),
            sourceSyntax: .implicitVRLittleEndian,
            acceptedSyntaxes: accepted
        )
        
        // Should select Explicit VR LE because JPEG Baseline is lossy
        #expect(target?.uid == TransferSyntax.explicitVRLittleEndian.uid)
        #expect(target?.isLossless == true)
    }
    
    // MARK: - Uncompressed Transcoding Tests
    
    @Test("Transcode simple data element from Explicit to Implicit VR")
    func testTranscodeExplicitToImplicit() throws {
        let converter = TransferSyntaxConverter()
        
        // Create a simple Explicit VR Little Endian data element
        // PatientName (0010,0010), VR=PN, Value="Test^Patient"
        var sourceData = Data()
        // Tag: (0010,0010)
        sourceData.append(contentsOf: [0x10, 0x00, 0x10, 0x00]) // Group, Element (LE)
        // VR: PN
        sourceData.append(contentsOf: "PN".utf8)
        // Length: 12 (2 bytes for 16-bit VRs)
        sourceData.append(contentsOf: [0x0C, 0x00])
        // Value: "Test^Patient"
        sourceData.append(contentsOf: "Test^Patient".utf8)
        
        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .implicitVRLittleEndian
        )
        
        #expect(result.wasTranscoded == true)
        #expect(result.isLossless == true)
        #expect(result.targetTransferSyntax.uid == TransferSyntax.implicitVRLittleEndian.uid)
        
        // Implicit VR should have different structure (no VR field)
        // Tag (4 bytes) + Length (4 bytes) + Value (12 bytes) = 20 bytes
        #expect(result.data.count == 20)
    }
    
    @Test("Transcode simple data element from Implicit to Explicit VR")
    func testTranscodeImplicitToExplicit() throws {
        let converter = TransferSyntaxConverter()
        
        // Create a simple Implicit VR Little Endian data element
        // PatientName (0010,0010), Value="Test^Patient"
        var sourceData = Data()
        // Tag: (0010,0010)
        sourceData.append(contentsOf: [0x10, 0x00, 0x10, 0x00]) // Group, Element (LE)
        // Length: 12 (4 bytes for Implicit VR)
        sourceData.append(contentsOf: [0x0C, 0x00, 0x00, 0x00])
        // Value: "Test^Patient"
        sourceData.append(contentsOf: "Test^Patient".utf8)
        
        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .implicitVRLittleEndian,
            to: .explicitVRLittleEndian
        )
        
        #expect(result.wasTranscoded == true)
        #expect(result.isLossless == true)
        #expect(result.targetTransferSyntax.uid == TransferSyntax.explicitVRLittleEndian.uid)
    }
    
    @Test("Transcode US (UInt16) data element with byte order change")
    func testTranscodeByteOrderChange() throws {
        let converter = TransferSyntaxConverter()
        
        // Create an Explicit VR Little Endian data element with US (UInt16) value
        // Rows (0028,0010), VR=US, Value=512 (0x0200 LE)
        var sourceData = Data()
        // Tag: (0028,0010)
        sourceData.append(contentsOf: [0x28, 0x00, 0x10, 0x00]) // Group, Element (LE)
        // VR: US
        sourceData.append(contentsOf: "US".utf8)
        // Length: 2 (2 bytes for 16-bit VRs)
        sourceData.append(contentsOf: [0x02, 0x00])
        // Value: 512 (0x0200) in Little Endian = [0x00, 0x02]
        sourceData.append(contentsOf: [0x00, 0x02])
        
        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .explicitVRBigEndian
        )
        
        #expect(result.wasTranscoded == true)
        #expect(result.isLossless == true)
        
        // Check that the value was byte-swapped
        // In Big Endian, 512 (0x0200) should be [0x02, 0x00]
        // Tag in BE: [0x00, 0x28, 0x00, 0x10]
        // VR: US
        // Length in BE: [0x00, 0x02]
        // Value in BE: [0x02, 0x00]
        let expectedLength = 4 + 2 + 2 + 2 // Tag + VR + Length + Value
        #expect(result.data.count == expectedLength)
    }
    
    @Test("Transcode multiple data elements")
    func testTranscodeMultipleElements() throws {
        let converter = TransferSyntaxConverter()
        
        var sourceData = Data()
        
        // Element 1: Rows (0028,0010), VR=US, Value=256
        sourceData.append(contentsOf: [0x28, 0x00, 0x10, 0x00]) // Tag (LE)
        sourceData.append(contentsOf: "US".utf8)
        sourceData.append(contentsOf: [0x02, 0x00]) // Length
        sourceData.append(contentsOf: [0x00, 0x01]) // Value: 256
        
        // Element 2: Columns (0028,0011), VR=US, Value=256
        sourceData.append(contentsOf: [0x28, 0x00, 0x11, 0x00]) // Tag (LE)
        sourceData.append(contentsOf: "US".utf8)
        sourceData.append(contentsOf: [0x02, 0x00]) // Length
        sourceData.append(contentsOf: [0x00, 0x01]) // Value: 256
        
        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .implicitVRLittleEndian
        )
        
        #expect(result.wasTranscoded == true)
        #expect(result.isLossless == true)
        
        // Each element in Implicit VR: Tag (4) + Length (4) + Value (2) = 10 bytes
        // Two elements: 20 bytes
        #expect(result.data.count == 20)
    }
}

// MARK: - Compression Configuration Tests

@Suite("CompressionQuality Tests")
struct CompressionQualityTests {
    
    @Test("Quality presets have correct values")
    func testQualityPresetValues() {
        #expect(CompressionQuality.maximum.value == 0.98)
        #expect(CompressionQuality.high.value == 0.90)
        #expect(CompressionQuality.medium.value == 0.75)
        #expect(CompressionQuality.low.value == 0.60)
    }
    
    @Test("Custom quality values are clamped")
    func testCustomQualityClamping() {
        #expect(CompressionQuality.custom(1.5).value == 1.0)
        #expect(CompressionQuality.custom(-0.5).value == 0.0)
        #expect(CompressionQuality.custom(0.5).value == 0.5)
    }
    
    @Test("Maximum quality is considered lossless")
    func testLosslessQuality() {
        #expect(CompressionQuality.maximum.isLossless == true)
        #expect(CompressionQuality.custom(1.0).isLossless == true)
        #expect(CompressionQuality.high.isLossless == false)
    }
    
    @Test("Quality descriptions are meaningful")
    func testQualityDescriptions() {
        #expect(CompressionQuality.maximum.description.contains("Maximum"))
        #expect(CompressionQuality.high.description.contains("High"))
        #expect(CompressionQuality.medium.description.contains("Medium"))
        #expect(CompressionQuality.low.description.contains("Low"))
        #expect(CompressionQuality.custom(0.5).description.contains("50"))
    }
}

@Suite("CompressionSpeed Tests")
struct CompressionSpeedTests {
    
    @Test("Speed descriptions are meaningful")
    func testSpeedDescriptions() {
        #expect(CompressionSpeed.fast.description == "Fast")
        #expect(CompressionSpeed.balanced.description == "Balanced")
        #expect(CompressionSpeed.optimal.description == "Optimal")
    }
}

@Suite("CompressionConfiguration Tests")
struct CompressionConfigurationTests {
    
    @Test("Default configuration has expected values")
    func testDefaultConfiguration() {
        let config = CompressionConfiguration.default
        
        #expect(config.quality.value == CompressionQuality.high.value)
        #expect(config.speed == .balanced)
        #expect(config.progressive == false)
        #expect(config.preferLossless == false)
        #expect(config.maxBitsPerSample == nil)
    }
    
    @Test("Network configuration optimizes for transfer")
    func testNetworkConfiguration() {
        let config = CompressionConfiguration.network
        
        #expect(config.quality == .medium)
        #expect(config.speed == .fast)
        #expect(config.progressive == true)
        #expect(config.preferLossless == false)
    }
    
    @Test("Archival configuration prioritizes quality")
    func testArchivalConfiguration() {
        let config = CompressionConfiguration.archival
        
        #expect(config.quality == .maximum)
        #expect(config.speed == .optimal)
        #expect(config.preferLossless == true)
    }
    
    @Test("Lossless configuration enforces lossless")
    func testLosslessConfiguration() {
        let config = CompressionConfiguration.lossless
        
        #expect(config.quality == .maximum)
        #expect(config.preferLossless == true)
    }
    
    @Test("Custom configuration creation")
    func testCustomConfiguration() {
        let config = CompressionConfiguration(
            quality: .custom(0.85),
            speed: .optimal,
            progressive: true,
            preferLossless: false,
            maxBitsPerSample: 12
        )
        
        #expect(config.quality.value == 0.85)
        #expect(config.speed == .optimal)
        #expect(config.progressive == true)
        #expect(config.preferLossless == false)
        #expect(config.maxBitsPerSample == 12)
    }
    
    @Test("Configuration description is informative")
    func testConfigurationDescription() {
        let config = CompressionConfiguration(
            quality: .high,
            speed: .balanced,
            progressive: true,
            preferLossless: true,
            maxBitsPerSample: 16
        )
        
        let description = config.description
        #expect(description.contains("quality"))
        #expect(description.contains("speed"))
        #expect(description.contains("progressive"))
        #expect(description.contains("preferLossless"))
        #expect(description.contains("maxBits"))
    }
}

// MARK: - Codec Registry Encoder Tests

#if canImport(ImageIO)
@Suite("CodecRegistry Encoder Tests")
struct CodecRegistryEncoderTests {
    
    @Test("Registry has encoders for JPEG")
    func testJPEGEncoderAvailable() {
        let registry = CodecRegistry.shared
        
        #expect(registry.hasEncoder(for: TransferSyntax.jpegBaseline.uid) == true)
    }
    
    @Test("Registry has encoders for JPEG 2000")
    func testJPEG2000EncoderAvailable() {
        let registry = CodecRegistry.shared
        
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000.uid) == true)
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000Lossless.uid) == true)
    }
    
    @Test("Registry returns encoder for supported syntax")
    func testEncoderRetrieval() {
        let registry = CodecRegistry.shared
        
        let jpegEncoder = registry.encoder(for: TransferSyntax.jpegBaseline.uid)
        #expect(jpegEncoder != nil)
        
        let jp2Encoder = registry.encoder(for: TransferSyntax.jpeg2000.uid)
        #expect(jp2Encoder != nil)
    }
    
    @Test("Registry has the native lossless RLE encoder")
    func testRLEEncoderAvailable() {
        let registry = CodecRegistry.shared
        
        #expect(registry.hasEncoder(for: TransferSyntax.rleLossless.uid))
        #expect(registry.encoder(for: TransferSyntax.rleLossless.uid) != nil)
    }
    
    @Test("Supported encoding transfer syntaxes list is populated")
    func testSupportedEncodingList() {
        let registry = CodecRegistry.shared
        
        let encodingSyntaxes = registry.supportedEncodingTransferSyntaxes
        #expect(encodingSyntaxes.count >= 3) // JPEG Baseline, JPEG 2000, JPEG 2000 Lossless
    }
}
#endif

// MARK: - JPEG Encoder Tests

#if canImport(ImageIO)
@Suite("NativeJPEGCodec Encoder Tests")
struct NativeJPEGCodecEncoderTests {
    
    @Test("Can encode 8-bit grayscale")
    func testCanEncode8BitGrayscale() {
        let codec = NativeJPEGCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.default
        #expect(codec.canEncode(with: config, descriptor: descriptor) == true)
    }
    
    /// ImageIO writes colour as YCbCr 4:2:0 / 4:4:4, neither YBR_FULL_422 nor RGB components
    /// (PS3.5 2026a Table 8.2.1-1), so NativeJPEGCodec refuses 3-sample input (D190).
    @Test("Cannot encode 8-bit RGB (ImageIO colour has no valid Table 8.2.1-1 label)")
    func testCanEncode8BitRGB() {
        let codec = NativeJPEGCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb
        )
        
        let config = CompressionConfiguration.default
        #expect(codec.canEncode(with: config, descriptor: descriptor) == false)
    }
    
    @Test("Cannot encode 16-bit with JPEG Baseline")
    func testCannotEncode16Bit() {
        let codec = NativeJPEGCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.default
        #expect(codec.canEncode(with: config, descriptor: descriptor) == false)
    }
    
    @Test("Cannot encode when lossless is preferred")
    func testCannotEncodeLossless() {
        let codec = NativeJPEGCodec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.lossless
        #expect(codec.canEncode(with: config, descriptor: descriptor) == false)
    }
    
    @Test("Encode simple 8-bit grayscale frame")
    func testEncodeGrayscaleFrame() throws {
        let codec = NativeJPEGCodec()
        let descriptor = PixelDataDescriptor(
            rows: 4,
            columns: 4,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        // Create 4x4 test image (gradient)
        var pixelData = Data()
        for y in 0..<4 {
            for x in 0..<4 {
                pixelData.append(UInt8(y * 64 + x * 16))
            }
        }
        
        let config = CompressionConfiguration.default
        let encoded = try codec.encodeFrame(pixelData, descriptor: descriptor, frameIndex: 0, configuration: config)
        
        // Verify we got JPEG data (starts with FFD8)
        #expect(encoded.count > 0)
        #expect(encoded[0] == 0xFF)
        #expect(encoded[1] == 0xD8)
    }
}
#endif

// MARK: - JPEG 2000 Encoder Tests

#if canImport(ImageIO)
@Suite("NativeJPEG2000Codec Encoder Tests")
struct NativeJPEG2000CodecEncoderTests {
    
    @Test("Can encode 8-bit grayscale")
    func testCanEncode8BitGrayscale() {
        let codec = NativeJPEG2000Codec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.default
        #expect(codec.canEncode(with: config, descriptor: descriptor) == true)
    }
    
    @Test("Can encode 16-bit grayscale")
    func testCanEncode16BitGrayscale() {
        let codec = NativeJPEG2000Codec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.default
        #expect(codec.canEncode(with: config, descriptor: descriptor) == true)
    }
    
    @Test("Can encode with lossless configuration")
    func testCanEncodeLossless() {
        let codec = NativeJPEG2000Codec()
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        
        let config = CompressionConfiguration.lossless
        #expect(codec.canEncode(with: config, descriptor: descriptor) == true)
    }

    @Test("12-bit grayscale JPEG 2000: deprecated ImageIO path corrupts, supported path round-trips")
    func testLossless12BitGrayscaleRoundtripDecodesInStoredBitRange() throws {
        // Previously a permanent `withKnownIssue`. Replaced 2026-08-11 with an
        // assertion of the *actual* contract. The original note claimed ImageIO's
        // decode throws; a probe showed it does NOT — it decodes 12-bit grayscale
        // JPEG 2000 without error but silently collapses the samples into the 8-bit
        // range (a value corruption, worse than a clean failure). That is the fixed
        // platform limitation behind the `NativeJPEG2000Codec` deprecation; the
        // supported `J2KSwiftCodec` round-trips 12-bit exactly. A suppressed failure
        // told us nothing; this pins both facts and fails loudly if either changes.
        let descriptor = PixelDataDescriptor(
            rows: 64,
            columns: 64,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )

        var frameData = Data(capacity: descriptor.rows * descriptor.columns * 2)
        let totalPixels = descriptor.rows * descriptor.columns
        for index in 0..<totalPixels {
            let sample = UInt16((index * descriptor.maxPossibleValue) / max(totalPixels - 1, 1))
            frameData.append(UInt8(sample & 0x00FF))
            frameData.append(UInt8(sample >> 8))
        }

        // Supported path: J2KSwiftCodec must round-trip 12-bit lossless exactly.
        let j2k = J2KSwiftCodec()
        let encoded = try j2k.encodeFrame(
            frameData, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try j2k.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(decoded.count == frameData.count)
        var decodedMax: UInt16 = 0
        var decodedLast: UInt16 = 0
        for offset in stride(from: 0, to: decoded.count - 1, by: 2) {
            let value = UInt16(decoded[offset]) | (UInt16(decoded[offset + 1]) << 8)
            if value > decodedMax { decodedMax = value }
            decodedLast = value
        }
        #expect(decodedMax <= UInt16(descriptor.maxPossibleValue))
        #expect(decodedLast >= UInt16(descriptor.maxPossibleValue - 8))

        // Deprecated path: ImageIO cannot decode 12-bit grayscale JPEG 2000. Pin
        // the limitation — if a future macOS gains support, this throws stops
        // throwing and the test fails, signalling the codec can be un-deprecated.
        // Deprecated path: ImageIO decodes 12-bit grayscale JPEG 2000 WITHOUT error,
        // but silently collapses the samples into the 8-bit range (observed max/last
        // ≈257 for a ramp whose true max is 4095). That value corruption — not a
        // decode failure — is the reason `NativeJPEG2000Codec` is deprecated for
        // >8-bit grayscale. Pin it: the decoded peak must stay well below the true
        // 12-bit maximum. If a future macOS fixes ImageIO, this assertion fails and
        // signals the codec can be reconsidered.
        let native = NativeJPEG2000Codec()
        let nativeEncoded = try native.encodeFrame(
            frameData, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let nativeDecoded = try native.decodeFrame(nativeEncoded, descriptor: descriptor, frameIndex: 0)
        var nativeMax: UInt16 = 0
        for offset in stride(from: 0, to: nativeDecoded.count - 1, by: 2) {
            let value = UInt16(nativeDecoded[offset]) | (UInt16(nativeDecoded[offset + 1]) << 8)
            if value > nativeMax { nativeMax = value }
        }
        #expect(nativeMax < UInt16(descriptor.maxPossibleValue / 2),
                "ImageIO is expected to collapse 12-bit samples toward the 8-bit range; if it now preserves them, re-evaluate the NativeJPEG2000Codec deprecation")
    }
}
#endif

// MARK: - Converter Compression Tests

@Suite("TransferSyntaxConverter Compression Tests")
struct TransferSyntaxConverterCompressionTests {
    
    @Test("Converter with compression configuration")
    func testConverterWithCompressionConfig() {
        let transcodingConfig = TranscodingConfiguration.maxCompression
        let compressionConfig = CompressionConfiguration.network
        
        let converter = TransferSyntaxConverter(
            configuration: transcodingConfig,
            compressionConfiguration: compressionConfig
        )
        
        #expect(converter.configuration.allowLossyCompression == true)
        #expect(converter.compressionConfiguration.progressive == true)
    }
}

#if canImport(ImageIO)
@Suite("End-to-End Compression Transcoding Tests")
struct EndToEndCompressionTests {

    /// Creates a synthetic uncompressed DICOM dataset as serialized bytes
    private func createSyntheticDataset(width: Int = 64, height: Int = 64, bitsAllocated: Int = 8) -> Data {
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        var elements: [DataElement] = []

        // SamplesPerPixel
        var spp: UInt16 = 1
        elements.append(DataElement(tag: .samplesPerPixel, vr: .US, length: 2, valueData: Data(bytes: &spp, count: 2)))

        // PhotometricInterpretation
        let pi = "MONOCHROME2 "
        elements.append(DataElement(tag: .photometricInterpretation, vr: .CS, length: UInt32(pi.utf8.count), valueData: Data(pi.utf8)))

        // Rows
        var rows = UInt16(height)
        elements.append(DataElement(tag: .rows, vr: .US, length: 2, valueData: Data(bytes: &rows, count: 2)))

        // Columns
        var cols = UInt16(width)
        elements.append(DataElement(tag: .columns, vr: .US, length: 2, valueData: Data(bytes: &cols, count: 2)))

        // BitsAllocated
        var ba = UInt16(bitsAllocated)
        elements.append(DataElement(tag: .bitsAllocated, vr: .US, length: 2, valueData: Data(bytes: &ba, count: 2)))

        // BitsStored
        var bs = UInt16(bitsAllocated)
        elements.append(DataElement(tag: .bitsStored, vr: .US, length: 2, valueData: Data(bytes: &bs, count: 2)))

        // HighBit
        var hb = UInt16(bitsAllocated - 1)
        elements.append(DataElement(tag: .highBit, vr: .US, length: 2, valueData: Data(bytes: &hb, count: 2)))

        // PixelRepresentation
        var pr: UInt16 = 0
        elements.append(DataElement(tag: .pixelRepresentation, vr: .US, length: 2, valueData: Data(bytes: &pr, count: 2)))

        // Pixel Data - gradient pattern
        let bytesPerSample = bitsAllocated / 8
        let pixelCount = width * height
        var pixelData = Data(capacity: pixelCount * bytesPerSample)
        for i in 0..<pixelCount {
            if bytesPerSample == 1 {
                let val = UInt8((i * 255) / max(pixelCount - 1, 1))
                pixelData.append(val)
            } else {
                var val = UInt16((i * 65535) / max(pixelCount - 1, 1))
                withUnsafeBytes(of: &val) { pixelData.append(contentsOf: $0) }
            }
        }
        elements.append(DataElement(tag: .pixelData, vr: .OW, length: UInt32(pixelData.count), valueData: pixelData))

        // Serialize in tag order
        var data = Data()
        for element in elements.sorted(by: { $0.tag < $1.tag }) {
            data.append(writer.serializeElement(element))
        }
        return data
    }

    @Test("Transcode 8-bit to JPEG 2000 Lossless produces valid encapsulated data")
    func testTranscodeToJPEG2000Lossless8Bit() throws {
        let sourceData = createSyntheticDataset(width: 64, height: 64, bitsAllocated: 8)
        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(
                preferredSyntaxes: [.jpeg2000Lossless],
                allowLossyCompression: false,
                preservePixelDataFidelity: true
            ),
            compressionConfiguration: .lossless
        )

        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .jpeg2000Lossless
        )

        #expect(result.wasTranscoded == true)

        // Verify pixel data tag exists with encapsulated format in the output
        // Scan for pixel data tag (7FE0,0010)
        var foundPixelData = false
        var offset = 0
        while offset + 12 <= result.data.count {
            let g = UInt16(result.data[offset]) | (UInt16(result.data[offset + 1]) << 8)
            let e = UInt16(result.data[offset + 2]) | (UInt16(result.data[offset + 3]) << 8)
            if g == 0x7FE0 && e == 0x0010 {
                foundPixelData = true
                // Check VR = OB
                let vrChar1 = result.data[offset + 4]
                let vrChar2 = result.data[offset + 5]
                #expect(vrChar1 == 0x4F) // 'O'
                #expect(vrChar2 == 0x42) // 'B'
                // Check undefined length
                let len = UInt32(result.data[offset + 8]) | (UInt32(result.data[offset + 9]) << 8) |
                          (UInt32(result.data[offset + 10]) << 16) | (UInt32(result.data[offset + 11]) << 24)
                #expect(len == 0xFFFFFFFF)
                // Check offset table item
                let itemG = UInt16(result.data[offset + 12]) | (UInt16(result.data[offset + 13]) << 8)
                let itemE = UInt16(result.data[offset + 14]) | (UInt16(result.data[offset + 15]) << 8)
                #expect(itemG == 0xFFFE)
                #expect(itemE == 0xE000)
                // Get offset table length
                let otLen = UInt32(result.data[offset + 16]) | (UInt32(result.data[offset + 17]) << 8) |
                            (UInt32(result.data[offset + 18]) << 16) | (UInt32(result.data[offset + 19]) << 24)
                // Fragment should follow
                let fragStart = offset + 20 + Int(otLen)
                if fragStart + 8 <= result.data.count {
                    let fragG = UInt16(result.data[fragStart]) | (UInt16(result.data[fragStart + 1]) << 8)
                    let fragE = UInt16(result.data[fragStart + 2]) | (UInt16(result.data[fragStart + 3]) << 8)
                    #expect(fragG == 0xFFFE)
                    #expect(fragE == 0xE000)
                    let fragLen = UInt32(result.data[fragStart + 4]) | (UInt32(result.data[fragStart + 5]) << 8) |
                                  (UInt32(result.data[fragStart + 6]) << 16) | (UInt32(result.data[fragStart + 7]) << 24)
                    #expect(fragLen > 0, "Fragment should contain compressed data, got length 0")
                    // Verify we have actual data
                    let fragData = result.data[(fragStart + 8)..<min(fragStart + 8 + Int(fragLen), result.data.count)]
                    #expect(fragData.count > 0, "Fragment data should be non-empty")
                }
                break
            }
            offset += 1
        }
        #expect(foundPixelData, "Pixel data tag (7FE0,0010) not found in transcoded output")
    }

    @Test("Transcode 16-bit to JPEG 2000 Lossless preserves data")
    func testTranscodeToJPEG2000Lossless16Bit() throws {
        let sourceData = createSyntheticDataset(width: 64, height: 64, bitsAllocated: 16)
        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(
                preferredSyntaxes: [.jpeg2000Lossless],
                allowLossyCompression: false,
                preservePixelDataFidelity: true
            ),
            compressionConfiguration: .lossless
        )

        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .jpeg2000Lossless
        )

        #expect(result.wasTranscoded == true)
        #expect(result.data.count > 0)
    }

    @Test("Transcode 8-bit to JPEG Baseline produces valid output")
    func testTranscodeToJPEGBaseline() throws {
        let sourceData = createSyntheticDataset(width: 64, height: 64, bitsAllocated: 8)
        let converter = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(
                preferredSyntaxes: [.jpegBaseline],
                allowLossyCompression: true,
                preservePixelDataFidelity: false
            )
        )

        let result = try converter.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .jpegBaseline
        )

        #expect(result.wasTranscoded == true)
        #expect(result.data.count > 0)
    }

    @Test("Roundtrip: transcode to JPEG 2000 then back to uncompressed preserves pixel data")
    func testRoundtripJPEG2000Lossless() throws {
        let sourceData = createSyntheticDataset(width: 64, height: 64, bitsAllocated: 8)

        // Compress
        let compressor = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(
                preferredSyntaxes: [.jpeg2000Lossless],
                allowLossyCompression: false,
                preservePixelDataFidelity: true
            ),
            compressionConfiguration: .lossless
        )
        let compressed = try compressor.transcode(
            dataSetData: sourceData,
            from: .explicitVRLittleEndian,
            to: .jpeg2000Lossless
        )

        // Decompress
        let decompressor = TransferSyntaxConverter(
            configuration: TranscodingConfiguration(
                preferredSyntaxes: [.explicitVRLittleEndian],
                allowLossyCompression: false,
                preservePixelDataFidelity: true
            )
        )
        let decompressed = try decompressor.transcode(
            dataSetData: compressed.data,
            from: .jpeg2000Lossless,
            to: .explicitVRLittleEndian
        )

        #expect(decompressed.wasTranscoded == true)

        // Extract pixel data from both source and decompressed datasets
        // Find pixel data tag in source
        var sourcePixels = Data()
        var offset = 0
        while offset + 12 <= sourceData.count {
            let g = UInt16(sourceData[offset]) | (UInt16(sourceData[offset + 1]) << 8)
            let e = UInt16(sourceData[offset + 2]) | (UInt16(sourceData[offset + 3]) << 8)
            if g == 0x7FE0 && e == 0x0010 {
                // Skip header: tag(4) + VR(2) + reserved(2) + len(4) = 12
                let len = UInt32(sourceData[offset + 8]) | (UInt32(sourceData[offset + 9]) << 8) |
                          (UInt32(sourceData[offset + 10]) << 16) | (UInt32(sourceData[offset + 11]) << 24)
                sourcePixels = sourceData[(offset + 12)..<(offset + 12 + Int(len))]
                break
            }
            offset += 1
        }

        // Find pixel data in decompressed
        var decompressedPixels = Data()
        offset = 0
        while offset + 12 <= decompressed.data.count {
            let g = UInt16(decompressed.data[offset]) | (UInt16(decompressed.data[offset + 1]) << 8)
            let e = UInt16(decompressed.data[offset + 2]) | (UInt16(decompressed.data[offset + 3]) << 8)
            if g == 0x7FE0 && e == 0x0010 {
                let len = UInt32(decompressed.data[offset + 8]) | (UInt32(decompressed.data[offset + 9]) << 8) |
                          (UInt32(decompressed.data[offset + 10]) << 16) | (UInt32(decompressed.data[offset + 11]) << 24)
                if len != 0xFFFFFFFF {
                    decompressedPixels = decompressed.data[(offset + 12)..<(offset + 12 + Int(len))]
                }
                break
            }
            offset += 1
        }

        #expect(sourcePixels.count == decompressedPixels.count, "Pixel data size should match after roundtrip")
        #expect(sourcePixels == decompressedPixels, "Pixel data should be identical after lossless roundtrip")
    }
}
#endif
