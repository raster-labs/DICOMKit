import Foundation
import Testing
@testable import DICOMCore
@testable import DICOMKit

@Suite("J2KSwiftCodec Tests")
struct J2KSwiftCodecTests {
    private func localDatasetsRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LocalDatasets/medical-dicom-organized", isDirectory: true)
    }

    private func firstDICOMFile(in relativeDirectory: String) -> URL? {
        let directory = localDatasetsRoot().appendingPathComponent(relativeDirectory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "dcm" {
            return fileURL
        }

        return nil
    }

    private func loadRealPixelSample(from relativeDirectory: String) throws -> (url: URL, file: DICOMFile, pixelData: PixelData) {
        guard let fileURL = firstDICOMFile(in: relativeDirectory) else {
            throw DICOMError.parsingFailed("No .dcm file found in LocalDatasets/medical-dicom-organized/\(relativeDirectory)")
        }

        let file = try DICOMFile.read(from: fileURL)
        let pixelData = try file.tryPixelData()
        return (fileURL, file, pixelData)
    }
    private func grayscale8Descriptor(rows: Int = 32, columns: Int = 32) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
    }

    private func grayscale16Descriptor(rows: Int = 32, columns: Int = 32) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
    }

    private func twelveBitDescriptor(rows: Int = 32, columns: Int = 32) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            bitsAllocated: 16,
            bitsStored: 12,
            highBit: 11,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
    }

    private func rgbDescriptor(rows: Int = 16, columns: Int = 16) -> PixelDataDescriptor {
        PixelDataDescriptor(
            rows: rows,
            columns: columns,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 3,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )
    }

    @Test("Supports JPEG 2000, Part 2, and HTJ2K transfer syntaxes")
    func supportedTransferSyntaxes() {
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.jpeg2000Lossless.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.jpeg2000.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.jpeg2000Part2Lossless.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.jpeg2000Part2.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.htj2kLossless.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.htj2kRPCLLossless.uid))
        #expect(J2KSwiftCodec.supportedTransferSyntaxes.contains(TransferSyntax.htj2kLossy.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.jpeg2000Lossless.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.jpeg2000.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.jpeg2000Part2Lossless.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.jpeg2000Part2.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.htj2kLossless.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.htj2kRPCLLossless.uid))
        #expect(J2KSwiftCodec.supportedEncodingTransferSyntaxes.contains(TransferSyntax.htj2kLossy.uid))
    }

    @Test("canEncode accepts supported descriptor layouts")
    func canEncodeSupportedLayouts() {
        let codec = J2KSwiftCodec()
        #expect(codec.canEncode(with: .lossless, descriptor: grayscale8Descriptor()))
        #expect(codec.canEncode(with: .lossless, descriptor: grayscale16Descriptor()))
        #expect(codec.canEncode(with: .default, descriptor: rgbDescriptor()))
    }

    @Test("canEncode rejects unsupported descriptor layouts")
    func canEncodeRejectsUnsupportedLayouts() {
        let codec = J2KSwiftCodec()

        let badBitDepth = PixelDataDescriptor(
            rows: 8,
            columns: 8,
            bitsAllocated: 32,
            bitsStored: 32,
            highBit: 31,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )

        let badSamplesPerPixel = PixelDataDescriptor(
            rows: 8,
            columns: 8,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 4,
            photometricInterpretation: .rgb,
            planarConfiguration: 0
        )

        #expect(codec.canEncode(with: .lossless, descriptor: badBitDepth) == false)
        #expect(codec.canEncode(with: .lossless, descriptor: badSamplesPerPixel) == false)
    }

    @Test("CodecRegistry exposes a JPEG 2000 codec and encoder")
    func registryResolvesCodec() {
        let registry = CodecRegistry.shared
        #expect(registry.hasCodec(for: TransferSyntax.jpeg2000Lossless.uid))
        #expect(registry.hasCodec(for: TransferSyntax.jpeg2000.uid))
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000Lossless.uid))
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000.uid))
    }

    @Test("CodecRegistry exposes Part 2 decoder and encoder")
    func registryResolvesPart2Codec() {
        let registry = CodecRegistry.shared
        #expect(registry.hasCodec(for: TransferSyntax.jpeg2000Part2Lossless.uid))
        #expect(registry.hasCodec(for: TransferSyntax.jpeg2000Part2.uid))
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000Part2Lossless.uid))
        #expect(registry.hasEncoder(for: TransferSyntax.jpeg2000Part2.uid))
    }

    @Test("TransferSyntax helpers recognize Part 2 and HTJ2K families")
    func transferSyntaxHelpersRecognizeExtendedFamilies() {
        #expect(TransferSyntax.jpeg2000Part2Lossless.isJPEG2000)
        #expect(TransferSyntax.jpeg2000Part2Lossless.isJPEG2000Part2)
        #expect(TransferSyntax.htj2kLossless.isJPEG2000)
        #expect(TransferSyntax.htj2kLossless.isHTJ2K)
        #expect(TransferSyntax.htj2kRPCLLossless.isHTJ2K)
        #expect(TransferSyntax.htj2kLossless.isLossless)
        #expect(TransferSyntax.htj2kLossy.isLossless == false)
    }

    @Test("Lossless 8-bit grayscale round-trip preserves payload")
    func lossless8BitRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = grayscale8Descriptor()
        let original = Data((0..<(descriptor.rows * descriptor.columns)).map { UInt8($0 % 251) })

        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == original.count)
        #if canImport(ImageIO)
        #expect(decoded == original)
        #endif
    }

    @Test("Lossless 16-bit grayscale round-trip preserves payload")
    func lossless16BitRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = grayscale16Descriptor()

        var original = Data(capacity: descriptor.bytesPerFrame)
        for index in 0..<(descriptor.rows * descriptor.columns) {
            let value = UInt16((index * 31) % 4096)
            original.append(UInt8(value & 0x00FF))
            original.append(UInt8((value >> 8) & 0x00FF))
        }

        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == original.count)
        #if canImport(ImageIO)
        #expect(decoded == original)
        #endif
    }

    @Test("12-bit grayscale in 16-bit container round-trip preserves payload size")
    func twelveBitRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = twelveBitDescriptor()

        var original = Data(capacity: descriptor.bytesPerFrame)
        for index in 0..<(descriptor.rows * descriptor.columns) {
            let value = UInt16((index * 17) % 4096)
            original.append(UInt8(value & 0x00FF))
            original.append(UInt8((value >> 8) & 0x00FF))
        }

        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == original.count)
    }

    @Test("Lossy grayscale round-trip preserves dimensions")
    func lossyGrayscaleRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = grayscale8Descriptor()
        let original = Data((0..<(descriptor.rows * descriptor.columns)).map { UInt8(($0 * 9) % 251) })

        let config = CompressionConfiguration(quality: .medium, speed: .balanced, progressive: false, preferLossless: false)
        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: config)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == original.count)
    }

    @Test("Lossless RGB round-trip preserves dimensions")
    func losslessRGBRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = rgbDescriptor()

        var original = Data(capacity: descriptor.bytesPerFrame)
        for y in 0..<descriptor.rows {
            for x in 0..<descriptor.columns {
                original.append(UInt8((x * 13) % 255))
                original.append(UInt8((y * 17) % 255))
                original.append(UInt8(((x + y) * 7) % 255))
            }
        }

        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == original.count)
    }

    @Test("Multi-frame lossless encode returns one fragment per frame")
    func multiFrameLosslessEncodeDecode() throws {
        let codec = J2KSwiftCodec()
        let descriptor = PixelDataDescriptor(
            rows: 16,
            columns: 16,
            numberOfFrames: 3,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )

        var original = Data(capacity: descriptor.bytesPerFrame * descriptor.numberOfFrames)
        for frameIndex in 0..<descriptor.numberOfFrames {
            for pixelIndex in 0..<(descriptor.rows * descriptor.columns) {
                original.append(UInt8((pixelIndex + frameIndex * 23) % 251))
            }
        }

        let frames = try codec.encode(original, descriptor: descriptor, configuration: .lossless)
        #expect(frames.count == descriptor.numberOfFrames)

        for frameIndex in 0..<frames.count {
            let decoded = try codec.decodeFrame(frames[frameIndex], descriptor: descriptor, frameIndex: frameIndex)
            let start = frameIndex * descriptor.bytesPerFrame
            let end = start + descriptor.bytesPerFrame
            #expect(decoded == original.subdata(in: start..<end))
        }
    }

    @Test("Lossy encode works across quality levels")
    func lossyQualityLevelsRoundTrip() throws {
        let codec = J2KSwiftCodec()
        let descriptor = grayscale8Descriptor(rows: 64, columns: 64)
        let original = Data((0..<(descriptor.rows * descriptor.columns)).map { UInt8(($0 * 5) % 251) })

        for quality in [0.25, 0.50, 0.75, 0.95] {
            let configuration = CompressionConfiguration(
                quality: .custom(quality),
                speed: .balanced,
                progressive: false,
                preferLossless: false
            )
            let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: configuration)
            let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

            #expect(encoded.isEmpty == false)
            #expect(decoded.count == original.count)
        }
    }

    @Test(
        "Real LocalDatasets DICOM files parse and expose pixel data",
        .enabled(if: LocalCodecFixtureAvailability.hasMRAndPX, "Requires optional MR and PX LocalDatasets fixtures")
    )
    func realDatasetFilesParseAndExposePixelData() throws {
        for relativeDirectory in ["mr", "px"] {
            let sample = try loadRealPixelSample(from: relativeDirectory)

            #expect(sample.url.pathExtension.lowercased() == "dcm")
            #expect(sample.file.transferSyntaxUID?.isEmpty == false)
            #expect(sample.pixelData.descriptor.rows > 0)
            #expect(sample.pixelData.descriptor.columns > 0)
            #expect(sample.pixelData.data.isEmpty == false)
        }
    }

    @Test(
        "Real LocalDatasets DICOM pixel data round-trips through J2KSwift",
        .enabled(if: LocalCodecFixtureAvailability.hasMR, "Requires optional MR LocalDatasets fixtures")
    )
    func realDatasetRoundTripThroughJ2KSwift() throws {
        let codec = J2KSwiftCodec()
        let sample = try loadRealPixelSample(from: "mr")
        let descriptor = sample.pixelData.descriptor

        #expect(codec.canEncode(with: .lossless, descriptor: descriptor))

        let encoded = try codec.encodeFrame(sample.pixelData.data, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)

        #expect(encoded.isEmpty == false)
        #expect(decoded.count == sample.pixelData.data.count)
    }

    @Test(
        "HTJ2K lossless and RPCL round-trip preserve payload size",
        .enabled(if: LocalCodecFixtureAvailability.hasMR, "Requires optional MR LocalDatasets fixtures")
    )
    func htj2kRoundTripPreservesPayloadSize() throws {
        let sample = try loadRealPixelSample(from: "mr")
        let descriptor = sample.pixelData.descriptor

        let htLosslessCodec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let htRPCLCodec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.htj2kRPCLLossless.uid)

        let htLosslessEncoded = try htLosslessCodec.encodeFrame(sample.pixelData.data, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let htLosslessDecoded = try htLosslessCodec.decodeFrame(htLosslessEncoded, descriptor: descriptor, frameIndex: 0)

        let htRPCLEncoded = try htRPCLCodec.encodeFrame(sample.pixelData.data, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let htRPCLDecoded = try htRPCLCodec.decodeFrame(htRPCLEncoded, descriptor: descriptor, frameIndex: 0)

        #expect(htLosslessEncoded.isEmpty == false)
        #expect(htRPCLEncoded.isEmpty == false)
        #expect(htLosslessDecoded.count == sample.pixelData.data.count)
        #expect(htRPCLDecoded.count == sample.pixelData.data.count)
    }

    @Test("Decoding empty data throws")
    func decodingEmptyDataThrows() {
        let codec = J2KSwiftCodec()
        #expect(throws: DICOMError.self) {
            try codec.decodeFrame(Data(), descriptor: grayscale8Descriptor(), frameIndex: 0)
        }
    }

    @Test("JPEG 2000 Part 2 lossless encode and decode round-trip")
    func part2LosslessEncodeRoundTrip() throws {
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Part2Lossless.uid)
        let descriptor = rgbDescriptor()
        let original = Data((0..<descriptor.bytesPerFrame).map { UInt8(($0 * 13) % 251) })
        #expect(codec.canEncode(with: .lossless, descriptor: descriptor))
        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: .lossless)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        #expect(decoded == original)
    }

    @Test("JPEG 2000 Part 2 lossy encode and decode round-trip")
    func part2LossyEncodeRoundTrip() throws {
        let codec = J2KSwiftCodec(encodingTransferSyntaxUID: TransferSyntax.jpeg2000Part2.uid)
        let descriptor = rgbDescriptor()
        let original = Data((0..<descriptor.bytesPerFrame).map { UInt8(($0 * 9) % 251) })
        let config = CompressionConfiguration(quality: .medium, speed: .balanced, progressive: false, preferLossless: false)
        #expect(codec.canEncode(with: config, descriptor: descriptor))
        let encoded = try codec.encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: config)
        let decoded = try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        #expect(decoded.count == original.count)
    }

    @Test("JPEG 2000 Part 2 parse aliases resolve correctly")
    func part2ParseAliases() {
        #expect(TransferSyntax.parse("j2k-part2") == .jpeg2000Part2)
        // `parse` is conservative: `…-lossless` and `…-lossless-only` both resolve to the
        // reversible-only .92 UID (the intent-into-.93 split lives in parseEncoding).
        #expect(TransferSyntax.parse("j2k-part2-lossless") == .jpeg2000Part2Lossless)
        #expect(TransferSyntax.parse("j2k-part2-lossless-only") == .jpeg2000Part2Lossless)
        #expect(TransferSyntax.parse("jpeg2000-part2") == .jpeg2000Part2)
        #expect(TransferSyntax.parse("jpeg2000-part2-lossless") == .jpeg2000Part2Lossless)
        #expect(TransferSyntax.parse("jpeg2000-part2-lossless-only") == .jpeg2000Part2Lossless)
    }
}


@Suite("J2KSwiftCodec strict frame decoding")
struct J2KSwiftCodecStrictDecodingTests {
    private static let lossless = TransferSyntax.jpeg2000Lossless.uid
    private static let general = TransferSyntax.jpeg2000.uid

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
        let encoded = try J2KSwiftCodec().encodeFrame(original, descriptor: descriptor, frameIndex: 0, configuration: configuration)
        return (original, encoded)
    }

    @Test("An exact lossless frame decodes byte-identically under every decoder instance")
    func exactFrame() throws {
        let descriptor = descriptor(rows: 16, columns: 16)
        let (original, encoded) = try encode(descriptor)
        #expect(J2KCodestreamInspector.usesIrreversibleWavelet(in: encoded) == false)
        for codec in [J2KSwiftCodec(), J2KSwiftCodec(decodingTransferSyntaxUID: Self.lossless), J2KSwiftCodec(decodingTransferSyntaxUID: Self.general)] {
            #expect(try codec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0) == original)
        }
    }

    @Test("Dimension mismatches throw")
    func dimensionMismatch() throws {
        let (_, encoded) = try encode(descriptor(rows: 16, columns: 16))
        for (rows, columns) in [(16, 15), (15, 16), (8, 32), (32, 32)] {
            #expect(throws: DICOMError.self, "\(columns)x\(rows)") {
                try J2KSwiftCodec().decodeFrame(encoded, descriptor: descriptor(rows: rows, columns: columns), frameIndex: 0)
            }
        }
    }

    @Test("Component count mismatches throw, including a surplus component under a single-sample descriptor")
    func componentMismatch() throws {
        let gray = descriptor(rows: 16, columns: 16)
        let rgb = descriptor(rows: 16, columns: 16, samples: 3)
        let (_, grayEncoded) = try encode(gray)
        let (_, rgbEncoded) = try encode(rgb)
        #expect(throws: DICOMError.self) { try J2KSwiftCodec().decodeFrame(rgbEncoded, descriptor: gray, frameIndex: 0) }
        #expect(throws: DICOMError.self) { try J2KSwiftCodec().decodeFrame(grayEncoded, descriptor: rgb, frameIndex: 0) }
    }

    @Test("A 16-bit codestream under an 8-bit descriptor throws instead of truncating")
    func precisionMismatch() throws {
        let wide = descriptor(rows: 16, columns: 16, bitsAllocated: 16, bitsStored: 16)
        let (original, encoded) = try encode(wide)
        #expect(try J2KSwiftCodec().decodeFrame(encoded, descriptor: wide, frameIndex: 0) == original)
        #expect(throws: DICOMError.self) {
            try J2KSwiftCodec().decodeFrame(encoded, descriptor: descriptor(rows: 16, columns: 16), frameIndex: 0)
        }
        // An 8-bit codestream under a 16-bit descriptor is a sample-width mismatch too.
        let (_, narrow) = try encode(descriptor(rows: 16, columns: 16))
        #expect(throws: DICOMError.self) {
            try J2KSwiftCodec().decodeFrame(narrow, descriptor: wide, frameIndex: 0)
        }
    }

    @Test("Irreversible 9/7 codestreams are refused under lossless-only syntaxes only")
    func irreversibleWavelet() throws {
        let descriptor = descriptor(rows: 16, columns: 16)
        let lossy = CompressionConfiguration(quality: .medium, speed: .balanced, progressive: false, preferLossless: false)
        let (_, encoded) = try encode(descriptor, configuration: lossy)
        try #require(J2KCodestreamInspector.usesIrreversibleWavelet(in: encoded))
        #expect(J2KSwiftCodec.irreversibleWaveletRefusal(frameData: encoded, transferSyntaxUID: Self.lossless) != nil)
        #expect(J2KSwiftCodec.irreversibleWaveletRefusal(frameData: encoded, transferSyntaxUID: Self.general) == nil)
        #expect(J2KSwiftCodec.irreversibleWaveletRefusal(frameData: encoded, transferSyntaxUID: nil) == nil)

        #expect(throws: DICOMError.self) {
            try J2KSwiftCodec(decodingTransferSyntaxUID: Self.lossless).decodeFrame(encoded, descriptor: descriptor, frameIndex: 0)
        }
        #expect(try J2KSwiftCodec(decodingTransferSyntaxUID: Self.general).decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 256)
        #expect(try J2KSwiftCodec().decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 256)

        let registry = CodecRegistry.shared
        let losslessCodec = try #require(registry.codec(for: Self.lossless))
        let generalCodec = try #require(registry.codec(for: Self.general))
        #expect(throws: DICOMError.self) { try losslessCodec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0) }
        #expect(try generalCodec.decodeFrame(encoded, descriptor: descriptor, frameIndex: 0).count == 256)
    }
}
