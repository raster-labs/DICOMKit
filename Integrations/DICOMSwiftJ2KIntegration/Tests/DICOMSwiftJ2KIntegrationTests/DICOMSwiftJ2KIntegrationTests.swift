import XCTest
import Foundation
import Synchronization
import DICOMCore
import DICOMKit
import DICOMSwiftJ2KIntegration
import SwiftJ2K

final class DICOMSwiftJ2KIntegrationTests: XCTestCase {

    // MARK: - Synthetic Dataset Builders (In-Memory & External Temp Directory Only)

    private func makeScratchDirectory(prefix: String = "m12-swiftj2k") throws -> URL {
        let root: URL
        if let envDir = ProcessInfo.processInfo.environment["SWIFTJ2K_M12_SCRATCH_DIR"], !envDir.isEmpty {
            root = URL(fileURLWithPath: envDir, isDirectory: true)
        } else {
            root = FileManager.default.temporaryDirectory
        }
        let dir = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeGrayscalePart10(
        rows: Int,
        columns: Int,
        frames: [ [Int] ],
        bitsAllocated: Int,
        bitsStored: Int,
        isSigned: Bool,
        photometric: String = "MONOCHROME2",
        clearUnusedHighBits: Bool = false,
        setUnusedHighBitsOverlay: UInt16 = 0,
        rescaleSlope: String? = nil,
        rescaleIntercept: String? = nil,
        windowCenter: String? = nil,
        windowWidth: String? = nil
    ) throws -> Data {
        let pixelsPerFrame = rows * columns
        XCTAssertTrue(frames.allSatisfy { $0.count == pixelsPerFrame })

        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setStrings(["ORIGINAL", "PRIMARY"], for: .imageType, vr: .CS)
        ds.setString("CT", for: .modality, vr: .CS)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString(photometric, for: .photometricInterpretation, vr: .CS)
        if frames.count > 1 {
            ds.setString("\(frames.count)", for: .numberOfFrames, vr: .IS)
        }
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(UInt16(bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(bitsStored - 1), for: .highBit)
        ds.setUInt16(isSigned ? 1 : 0, for: .pixelRepresentation)
        if let rescaleSlope {
            ds.setString(rescaleSlope, for: .rescaleSlope, vr: .DS)
        }
        if let rescaleIntercept {
            ds.setString(rescaleIntercept, for: .rescaleIntercept, vr: .DS)
        }
        if let windowCenter {
            ds.setString(windowCenter, for: .windowCenter, vr: .DS)
        }
        if let windowWidth {
            ds.setString(windowWidth, for: .windowWidth, vr: .DS)
        }

        let bytesPerSample = bitsAllocated / 8
        let mask = UInt16((1 << bitsStored) - 1)
        var raw = Data(capacity: frames.count * pixelsPerFrame * bytesPerSample)
        for frame in frames {
            for sample in frame {
                if bytesPerSample == 1 {
                    let byte = isSigned
                        ? UInt8(bitPattern: Int8(truncatingIfNeeded: sample))
                        : UInt8(truncatingIfNeeded: sample)
                    raw.append(byte)
                } else {
                    var word: UInt16
                    if isSigned {
                        let signedWord = UInt16(bitPattern: Int16(truncatingIfNeeded: sample))
                        word = clearUnusedHighBits ? (signedWord & mask) : signedWord
                    } else {
                        word = (UInt16(truncatingIfNeeded: sample) & mask) | (setUnusedHighBitsOverlay & ~mask)
                    }
                    raw.append(UInt8(word & 0xFF))
                    raw.append(UInt8(word >> 8))
                }
            }
        }
        ds[.pixelData] = DataElement(
            tag: .pixelData,
            vr: bitsAllocated > 8 ? .OW : .OB,
            length: UInt32(raw.count),
            valueData: raw
        )
        return try DICOMFile.create(
            dataSet: ds,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        ).write()
    }

    private func makeRGBPart10(
        rows: Int,
        columns: Int,
        frames: Int,
        bitsAllocated: Int = 8,
        bitsStored: Int = 8,
        planarConfiguration: Int = 0
    ) throws -> (part10: Data, expectedFrames: [Data]) {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.7", for: .sopClassUID, vr: .UI)
        ds.setString(UIDGenerator.generateSOPInstanceUID().value, for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(3, for: .samplesPerPixel)
        ds.setString("RGB", for: .photometricInterpretation, vr: .CS)
        ds.setUInt16(UInt16(planarConfiguration), for: .planarConfiguration)
        if frames > 1 {
            ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
        }
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(columns), for: .columns)
        ds.setUInt16(UInt16(bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(bitsStored - 1), for: .highBit)
        ds.setUInt16(0, for: .pixelRepresentation)

        let maxVal = (1 << bitsStored) - 1
        let bytesPerSample = bitsAllocated / 8
        let pixelCount = rows * columns
        var allBytes = Data()
        var perFrame: [Data] = []

        for f in 0..<frames {
            var frameData = Data()
            if planarConfiguration == 1 {
                for c in 0..<3 {
                    for p in 0..<pixelCount {
                        let v = ((p * (c + 3) + f * 29 + c * 41) & maxVal)
                        if bytesPerSample == 1 {
                            frameData.append(UInt8(v))
                        } else {
                            let w = UInt16(v)
                            frameData.append(UInt8(w & 0xFF))
                            frameData.append(UInt8(w >> 8))
                        }
                    }
                }
            } else {
                for p in 0..<pixelCount {
                    for c in 0..<3 {
                        let v = ((p * (c + 3) + f * 29 + c * 41) & maxVal)
                        if bytesPerSample == 1 {
                            frameData.append(UInt8(v))
                        } else {
                            let w = UInt16(v)
                            frameData.append(UInt8(w & 0xFF))
                            frameData.append(UInt8(w >> 8))
                        }
                    }
                }
            }
            perFrame.append(frameData)
            allBytes.append(frameData)
        }

        ds[.pixelData] = DataElement(
            tag: .pixelData,
            vr: bitsAllocated > 8 ? .OW : .OB,
            length: UInt32(allBytes.count),
            valueData: allBytes
        )
        let part10 = try DICOMFile.create(
            dataSet: ds,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        ).write()
        return (part10, perFrame)
    }

    private func extractLogicalGrayscaleSamples(
        from file: DICOMFile,
        codecRegistry: CodecRegistry
    ) throws -> [[Int]] {
        try Self.extractLogicalGrayscaleSamples(from: file, codecRegistry: codecRegistry)
    }

    private static func extractLogicalGrayscaleSamples(
        from file: DICOMFile,
        codecRegistry: CodecRegistry
    ) throws -> [[Int]] {
        let pixelData = try file.tryPixelData(codecRegistry: codecRegistry)
        let d = pixelData.descriptor
        var allFrames: [[Int]] = []
        for f in 0..<d.numberOfFrames {
            guard let frameBytes = pixelData.frameData(at: f) else {
                XCTFail("Missing frame \(f)")
                return []
            }
            let samples: [Int] = frameBytes.withUnsafeBytes { raw in
                var values: [Int] = []
                values.reserveCapacity(d.pixelsPerFrame)
                for p in 0..<d.pixelsPerFrame {
                    let cell = d.cellValue(in: raw, at: p * d.bytesPerSample)
                    values.append(d.storedValue(fromCell: cell))
                }
                return values
            }
            allFrames.append(samples)
        }
        return allFrames
    }

    // MARK: - 1. Multi-Frame Grayscale Exact Sample & Metadata Matrix (Signed 12-in-16 & Unsigned 16-Bit Extrema)

    func testSigned12In16SignExtendedAndClearedUnusedBitsCrossCodecAndMetadata() throws {
        let rows = 16
        let columns = 16
        let count = rows * columns
        let anchors = [-2048, -2047, -1024, -512, -1, 0, 1, 511, 1023, 2046, 2047]
        let expectedFrames: [[Int]] = (0..<3).map { f in
            (0..<count).map { idx in
                if idx < anchors.count {
                    return anchors[(idx + f * 3) % anchors.count]
                }
                let span = 4096
                let raw = ((idx * 37 + f * 509) % span) - 2048
                return max(-2048, min(2047, raw))
            }
        }

        let signExtendedPart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: expectedFrames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: true,
            photometric: "MONOCHROME2",
            clearUnusedHighBits: false,
            rescaleSlope: "1.5",
            rescaleIntercept: "-1024",
            windowCenter: "40",
            windowWidth: "400"
        )
        let clearedHighBitsPart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: expectedFrames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: true,
            photometric: "MONOCHROME1",
            clearUnusedHighBits: true,
            rescaleSlope: "1.5",
            rescaleIntercept: "-1024",
            windowCenter: "40",
            windowWidth: "400"
        )

        let collector = SwiftJ2KTelemetryCollector()
        let swiftRegistry = CodecRegistry.swiftJ2K(options: SwiftJ2KProviderOptions(collector: collector))
        let predecessorRegistry = CodecRegistry.j2kSwiftRollback

        let codecs = [
            "jpeg2000-lossless-only",
            "jpeg2000-lossless",
            "htj2k-lossless-only",
            "htj2k-rpcl-lossless-only",
            "htj2k-lossless"
        ]

        // A. Successor encode (both sign-extended AND cleared unused high bits) -> Successor & Predecessor decode
        for (variantIndex, inputPart10) in [signExtendedPart10, clearedHighBitsPart10].enumerated() {
            let expectedPI = variantIndex == 0 ? "MONOCHROME2" : "MONOCHROME1"
            for codec in codecs {
                collector.reset()
                let (compressed, metrics) = try CompressionManager(codecRegistry: swiftRegistry)
                    .compressDataWithMetrics(inputPart10, codec: codec, quality: nil)
                XCTAssertEqual(metrics.resolvedEncodeProviderID, .swiftJ2K, "codec=\(codec)")
                XCTAssertEqual(collector.records.count, 3, "Expected one SwiftJ2K encode report per frame")
                XCTAssertTrue(collector.records.allSatisfy {
                    $0.kind == .encode && $0.report.backend == .scalarCPU && $0.report.fidelity == .exactSamples
                })

                let compressedFile = try DICOMFile.read(from: compressed, options: .init(strictEncapsulation: true))
                XCTAssertEqual(compressedFile.dataSet.uint16(for: .bitsAllocated), 16)
                XCTAssertEqual(compressedFile.dataSet.uint16(for: .bitsStored), 12)
                XCTAssertEqual(compressedFile.dataSet.uint16(for: .highBit), 11)
                XCTAssertEqual(compressedFile.dataSet.uint16(for: .pixelRepresentation), 1)
                XCTAssertEqual(compressedFile.dataSet.string(for: .photometricInterpretation), expectedPI)
                XCTAssertEqual(compressedFile.dataSet.string(for: .rescaleSlope), "1.5")
                XCTAssertEqual(compressedFile.dataSet.string(for: .rescaleIntercept), "-1024")
                XCTAssertEqual(compressedFile.dataSet.string(for: .windowCenter), "40")
                XCTAssertEqual(compressedFile.dataSet.string(for: .windowWidth), "400")

                // Decode with SwiftJ2K
                let swiftSamples = try extractLogicalGrayscaleSamples(from: compressedFile, codecRegistry: swiftRegistry)
                XCTAssertEqual(swiftSamples, expectedFrames, "SwiftJ2K decode mismatch for \(codec) variant \(variantIndex)")

                // Decode with predecessor J2KSwift (cross-codec verification)
                let predSamples = try extractLogicalGrayscaleSamples(from: compressedFile, codecRegistry: predecessorRegistry)
                XCTAssertEqual(predSamples, expectedFrames, "Predecessor J2KSwift decode mismatch for SwiftJ2K-encoded \(codec) variant \(variantIndex)")

                // Verify canonical sign-extended Int16 cell bytes in decompressed native dataset
                let (decompressed, decProvider) = try CompressionManager(codecRegistry: swiftRegistry)
                    .decompressDataWithMetrics(compressed)
                XCTAssertEqual(decProvider, .swiftJ2K)
                let decompressedFile = try DICOMFile.read(from: decompressed)
                guard let nativeBytes = decompressedFile.dataSet[.pixelData]?.valueData else {
                    return XCTFail("Missing native pixel bytes")
                }
                // Check first anchor (-2048 -> 0xF800) and -1 (0xFFFF) are canonically sign-extended in 16-bit cells
                nativeBytes.withUnsafeBytes { raw in
                    let firstCell = UInt16(raw[0]) | (UInt16(raw[1]) << 8)
                    XCTAssertEqual(Int16(bitPattern: firstCell), Int16(expectedFrames[0][0]))
                    let minusOneIdx = expectedFrames[0].firstIndex(of: -1)!
                    let minusOneCell = UInt16(raw[minusOneIdx * 2]) | (UInt16(raw[minusOneIdx * 2 + 1]) << 8)
                    XCTAssertEqual(minusOneCell, 0xFFFF, "Decoded signed 12-in-16 -1 cell must be canonical two's-complement 0xFFFF")
                }
            }
        }

        // B. Predecessor J2KSwift encode -> Successor SwiftJ2K decode across all lossless syntaxes
        for codec in codecs {
            let (predCompressed, predMetrics) = try CompressionManager(codecRegistry: predecessorRegistry)
                .compressDataWithMetrics(signExtendedPart10, codec: codec, quality: nil)
            XCTAssertEqual(predMetrics.resolvedEncodeProviderID, .j2kSwift)
            let predFile = try DICOMFile.read(from: predCompressed, options: .init(strictEncapsulation: true))

            collector.reset()
            let decodedBySwiftJ2K = try extractLogicalGrayscaleSamples(from: predFile, codecRegistry: swiftRegistry)
            XCTAssertEqual(decodedBySwiftJ2K, expectedFrames, "SwiftJ2K decode mismatch on J2KSwift-encoded \(codec)")
            XCTAssertEqual(collector.records.count, 3)
            XCTAssertTrue(collector.records.allSatisfy {
                $0.kind == .decode
                    && $0.report.backend == .scalarCPU
                    && $0.report.fidelity == .exactSamples
                    && $0.report.pixelAllocationCount == 0
            })
        }
    }

    func testUnsigned16BitExtremaUnsigned12WithOverlayAndSigned16CrossCodec() throws {
        let rows = 16
        let columns = 16
        let count = rows * columns

        // 1. Unsigned 16-bit with exact extrema (0, 1, 32767, 32768, 65534, 65535)
        let u16Anchors = [0, 1, 2, 255, 256, 4095, 4096, 32767, 32768, 65534, 65535]
        let u16Frames: [[Int]] = (0..<3).map { f in
            (0..<count).map { idx in
                if idx < u16Anchors.count {
                    return u16Anchors[(idx + f * 2) % u16Anchors.count]
                }
                return (idx * 257 + f * 4099) & 0xFFFF
            }
        }
        let u16Part10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: u16Frames,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )

        let swiftRegistry = CodecRegistry.swiftJ2K()
        let predRegistry = CodecRegistry.j2kSwiftRollback

        for codec in ["jpeg2000-lossless-only", "htj2k-lossless-only", "htj2k-rpcl-lossless-only"] {
            // Predecessor -> Successor
            let predEncoded = try CompressionManager(codecRegistry: predRegistry)
                .compressData(u16Part10, codec: codec, quality: nil)
            let predFile = try DICOMFile.read(from: predEncoded, options: .init(strictEncapsulation: true))
            XCTAssertEqual(try extractLogicalGrayscaleSamples(from: predFile, codecRegistry: swiftRegistry), u16Frames)

            // Successor -> Predecessor
            let swiftEncoded = try CompressionManager(codecRegistry: swiftRegistry)
                .compressData(u16Part10, codec: codec, quality: nil)
            let swiftFile = try DICOMFile.read(from: swiftEncoded, options: .init(strictEncapsulation: true))
            XCTAssertEqual(try extractLogicalGrayscaleSamples(from: swiftFile, codecRegistry: predRegistry), u16Frames)
            XCTAssertEqual(try extractLogicalGrayscaleSamples(from: swiftFile, codecRegistry: swiftRegistry), u16Frames)
        }

        // 2. Unsigned 12-in-16 with non-zero unused overlay bits (0xA000) masked cleanly on encode
        let u12Frames: [[Int]] = (0..<2).map { f in
            (0..<count).map { idx in
                idx == 0 ? 0 : (idx == 1 ? 4095 : ((idx * 19 + f * 331) & 0x0FFF))
            }
        }
        let u12OverlayPart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: u12Frames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: false,
            setUnusedHighBitsOverlay: 0xA000
        )
        let u12Encoded = try CompressionManager(codecRegistry: swiftRegistry)
            .compressData(u12OverlayPart10, codec: "htj2k-lossless-only", quality: nil)
        let u12File = try DICOMFile.read(from: u12Encoded)
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: u12File, codecRegistry: predRegistry), u12Frames)

        // 3. Signed 16-bit full-range extrema (-32768, -1, 0, 32767)
        let s16Anchors = [-32768, -32767, -16384, -1, 0, 1, 16383, 32766, 32767]
        let s16Frames: [[Int]] = [
            (0..<count).map { idx in idx < s16Anchors.count ? s16Anchors[idx] : (((idx * 521) & 0xFFFF) - 32768) }
        ]
        let s16Part10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: s16Frames,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: true
        )
        let s16SwiftEncoded = try CompressionManager(codecRegistry: swiftRegistry)
            .compressData(s16Part10, codec: "jpeg2000-lossless-only", quality: nil)
        XCTAssertEqual(
            try extractLogicalGrayscaleSamples(from: DICOMFile.read(from: s16SwiftEncoded), codecRegistry: predRegistry),
            s16Frames
        )
    }

    // MARK: - 2. Compressed-Domain SwiftJ2K.Transcoder (J2K <-> HTJ2K) & Multi-Frame BOT Rebuild

    func testCompressedDomainTranscoderBothDirectionsRebuildsBOTAndPreservesSamples() throws {
        let rows = 24
        let columns = 24
        let count = rows * columns
        let frames: [[Int]] = (0..<3).map { f in
            (0..<count).map { idx in
                if idx == 0 { return 0 }
                if idx == 1 { return 65535 }
                // Vary entropy across frames so frame codestream sizes differ
                return f == 0 ? ((idx * 3) & 0xFFFF) : (f == 1 ? ((idx * 7919 + 12345) & 0xFFFF) : ((idx & 1) * 65535))
            }
        }
        let nativePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: frames,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )

        let predRegistry = CodecRegistry.j2kSwiftRollback
        let collector = SwiftJ2KTelemetryCollector()
        let swiftRegistry = CodecRegistry.swiftJ2K(options: SwiftJ2KProviderOptions(collector: collector))

        // Verify predecessor compressedDomainTranscoder stays disabled
        XCTAssertNil(J2KCodecProvider.j2kSwift.compressedDomainTranscoder)

        // Start from predecessor-encoded .90 Part-10 file, replacing BOT with valid EOT + EOT Lengths
        // to prove canonical EOT frame resolution during compressed-domain transcode AND EOT stripping + BOT rebuild on output
        let predJ2KBytes = try CompressionManager(codecRegistry: predRegistry)
            .compressData(nativePart10, codec: "jpeg2000-lossless-only", quality: nil)
        let rawPredJ2KFile = try DICOMFile.read(from: predJ2KBytes, options: .init(strictEncapsulation: true))
        let predFrags = try XCTUnwrap(rawPredJ2KFile.dataSet[.pixelData]?.encapsulatedFragments)
        var eotOffsets = Data()
        var eotLengths = Data()
        var runningItemOffset: UInt64 = 0
        for frag in predFrags {
            var leOffset = runningItemOffset.littleEndian
            let hasMarkerPad = frag.count >= 6
                && frag.count % 2 == 0
                && frag.last == 0
                && frag[frag.endIndex - 3] == 0xFF
                && frag[frag.endIndex - 2] == 0xD9
            let logicalLen = hasMarkerPad ? (frag.count - 1) : frag.count
            var leLength = UInt64(logicalLen).littleEndian
            withUnsafeBytes(of: &leOffset) { eotOffsets.append(contentsOf: $0) }
            withUnsafeBytes(of: &leLength) { eotLengths.append(contentsOf: $0) }
            runningItemOffset += UInt64(8 + frag.count + (frag.count % 2))
        }
        var eotDataSet = rawPredJ2KFile.dataSet
        eotDataSet[.pixelData] = DataElement(
            tag: .pixelData,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: predFrags,
            encapsulatedOffsetTable: []
        )
        eotDataSet[.extendedOffsetTable] = DataElement(
            tag: .extendedOffsetTable,
            vr: .OV,
            length: UInt32(eotOffsets.count),
            valueData: eotOffsets
        )
        eotDataSet[.extendedOffsetTableLengths] = DataElement(
            tag: .extendedOffsetTableLengths,
            vr: .OV,
            length: UInt32(eotLengths.count),
            valueData: eotLengths
        )
        let predJ2KFile = DICOMFile(fileMetaInformation: rawPredJ2KFile.fileMetaInformation, dataSet: eotDataSet)

        // Convert .90 -> .201 via DICOMConverter with SwiftJ2K registry
        collector.reset()
        let toHTJ2K = try DICOMConverter.convertToDICOM(
            dicomFile: predJ2KFile,
            to: .init(transferSyntax: .htj2kLossless, intent: .notApplicable),
            stripPrivate: false,
            codecRegistry: swiftRegistry
        )
        XCTAssertTrue(toHTJ2K.wasTranscoded)
        XCTAssertTrue(toHTJ2K.isLossless)
        XCTAssertEqual(toHTJ2K.resolvedTranscodeProviderID, .swiftJ2K)
        XCTAssertNil(toHTJ2K.resolvedDecodeProviderID)
        XCTAssertNil(toHTJ2K.resolvedEncodeProviderID)
        XCTAssertEqual(collector.records.count, 3)
        XCTAssertEqual(collector.records.map(\.frameIndex), [0, 1, 2])
        XCTAssertTrue(collector.records.allSatisfy {
            $0.kind == .transcode
                && $0.report.backend == .scalarCPU
                && $0.dicomBackend == .scalar
                && $0.report.fidelity == .exactSamples
                && $0.report.pixelAllocationCount == 0
                && $0.report.peakPixelBytes == 0
        })

        let htj2kFile = try DICOMFile.read(from: toHTJ2K.data, options: .init(strictEncapsulation: true))
        XCTAssertEqual(htj2kFile.transferSyntaxUID, TransferSyntax.htj2kLossless.uid)
        XCTAssertNil(htj2kFile.dataSet[.extendedOffsetTable])
        XCTAssertNil(htj2kFile.dataSet[.extendedOffsetTableLengths])
        let htj2kFragments = try XCTUnwrap(htj2kFile.dataSet[.pixelData]?.encapsulatedFragments)
        let htj2kBOT = try XCTUnwrap(htj2kFile.dataSet[.pixelData]?.encapsulatedOffsetTable)
        XCTAssertEqual(htj2kFragments.count, 3)
        let expectedBOT = try EncapsulatedPixelData.buildCheckedBasicOffsetTable(for: htj2kFragments).offsets
        XCTAssertEqual(htj2kBOT, expectedBOT, "Rebuilt BOT offsets must match changed HTJ2K frame lengths")

        // Both J2KSwift and SwiftJ2K decode exact samples from the compressed-domain transcoded HTJ2K file
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: htj2kFile, codecRegistry: predRegistry), frames)
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: htj2kFile, codecRegistry: swiftRegistry), frames)

        // Reverse direction: HTJ2K (.201) -> Part 1 (.90) via compressed-domain SwiftJ2K.Transcoder
        collector.reset()
        let backToJ2K = try DICOMConverter.convertToDICOM(
            dicomFile: htj2kFile,
            to: .init(transferSyntax: .jpeg2000Lossless, intent: .notApplicable),
            stripPrivate: false,
            codecRegistry: swiftRegistry
        )
        XCTAssertEqual(backToJ2K.resolvedTranscodeProviderID, .swiftJ2K)
        XCTAssertEqual(collector.records.count, 3)
        XCTAssertTrue(collector.records.allSatisfy { $0.kind == .transcode && $0.report.pixelAllocationCount == 0 })

        let roundTrippedJ2KFile = try DICOMFile.read(from: backToJ2K.data, options: .init(strictEncapsulation: true))
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: roundTrippedJ2KFile, codecRegistry: predRegistry), frames)
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: roundTrippedJ2KFile, codecRegistry: swiftRegistry), frames)
        _ = predJ2KFile
    }

    func testSignedAndRGBTranscodesRouteThroughPixelDecodeEncodeWithExactSamples() throws {
        let rows = 16
        let columns = 16
        let signedFrames: [[Int]] = [
            (0..<(rows * columns)).map { idx in ((idx * 17) % 4096) - 2048 },
            (0..<(rows * columns)).map { idx in ((idx * 31 + 7) % 4096) - 2048 }
        ]
        let signedPart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: signedFrames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: true
        )

        let collector = SwiftJ2KTelemetryCollector()
        let swiftRegistry = CodecRegistry.swiftJ2K(options: SwiftJ2KProviderOptions(collector: collector))
        let signedJ2K = try CompressionManager(codecRegistry: swiftRegistry)
            .compressData(signedPart10, codec: "jpeg2000-lossless-only", quality: nil)

        collector.reset()
        let convertedSigned = try DICOMConverter.convertToDICOM(
            dicomFile: DICOMFile.read(from: signedJ2K),
            to: .init(transferSyntax: .htj2kLossless, intent: .notApplicable),
            stripPrivate: false,
            codecRegistry: swiftRegistry
        )
        XCTAssertNil(convertedSigned.resolvedTranscodeProviderID)
        XCTAssertEqual(convertedSigned.resolvedDecodeProviderID, .swiftJ2K)
        XCTAssertEqual(convertedSigned.resolvedEncodeProviderID, .swiftJ2K)
        XCTAssertEqual(
            try extractLogicalGrayscaleSamples(from: DICOMFile.read(from: convertedSigned.data), codecRegistry: .j2kSwiftRollback),
            signedFrames
        )

        // 3-component RGB (chunky and planar) lossless round-trip & YBR_RCT -> RGB restoration
        let (_, chunkyExpectedFrames) = try makeRGBPart10(
            rows: 16,
            columns: 16,
            frames: 2,
            bitsAllocated: 8,
            bitsStored: 8,
            planarConfiguration: 0
        )
        for planar in [0, 1] {
            let (rgbPart10, _) = try makeRGBPart10(
                rows: 16,
                columns: 16,
                frames: 2,
                bitsAllocated: 8,
                bitsStored: 8,
                planarConfiguration: planar
            )
            let rgbCompressed = try CompressionManager(codecRegistry: swiftRegistry)
                .compressData(rgbPart10, codec: "htj2k-lossless-only", quality: nil)
            let rgbEncFile = try DICOMFile.read(from: rgbCompressed, options: .init(strictEncapsulation: true))
            XCTAssertEqual(rgbEncFile.dataSet.string(for: .photometricInterpretation), "YBR_RCT")
            XCTAssertEqual(rgbEncFile.dataSet.uint16(for: .planarConfiguration), 0)

            // Decode via pixelData & decompressDataWithMetrics, and cross-decode via J2KSwift
            for f in 0..<2 {
                let swiftFrame = try XCTUnwrap(rgbEncFile.pixelData(frame: f, codecRegistry: swiftRegistry))
                let predFrame = try XCTUnwrap(rgbEncFile.pixelData(frame: f, codecRegistry: .j2kSwiftRollback))
                XCTAssertEqual(swiftFrame.data, chunkyExpectedFrames[f])
                XCTAssertEqual(predFrame.data, chunkyExpectedFrames[f])
            }
            let (rgbDecompressed, _) = try CompressionManager(codecRegistry: swiftRegistry)
                .decompressDataWithMetrics(rgbCompressed)
            let rgbDecFile = try DICOMFile.read(from: rgbDecompressed)
            XCTAssertEqual(rgbDecFile.dataSet.string(for: .photometricInterpretation), "RGB")
        }
    }

    // MARK: - 3. Lossy Part 1 (.91) PSNR Tolerance & DICOM Lossy Provenance

    func testLossyPart1EncodeDecodePSNRAndProvenanceAcrossProviders() throws {
        let rows = 64
        let columns = 64
        let frame0 = (0..<(rows * columns)).map { idx in
            let r = idx / columns
            let c = idx % columns
            return (r * 512 + c * 512) & 0xFFFF
        }
        let frame1 = (0..<(rows * columns)).map { idx in
            let r = idx / columns
            let c = idx % columns
            return ((63 - r) * 512 + c * 512) & 0xFFFF
        }
        let nativePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: [frame0, frame1],
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )
        let originalFile = try DICOMFile.read(from: nativePart10)
        let originalSOP = originalFile.dataSet.string(for: .sopInstanceUID)

        let collector = SwiftJ2KTelemetryCollector()
        let swiftRegistry = CodecRegistry.swiftJ2K(options: SwiftJ2KProviderOptions(collector: collector))

        let outcome = try DICOMConverter.convertToDICOM(
            dicomFile: originalFile,
            to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding("jpeg2000-lossy")),
            stripPrivate: false,
            codecRegistry: swiftRegistry
        )
        XCTAssertFalse(outcome.isLossless)
        XCTAssertEqual(outcome.resolvedEncodeProviderID, .swiftJ2K)
        XCTAssertTrue(collector.records.allSatisfy { $0.kind == .encode && $0.report.fidelity == .lossy })

        let lossyFile = try DICOMFile.read(from: outcome.data, options: .init(strictEncapsulation: true))
        XCTAssertEqual(lossyFile.transferSyntaxUID, TransferSyntax.jpeg2000.uid)
        XCTAssertEqual(lossyFile.dataSet.string(for: .lossyImageCompression), "01")
        XCTAssertEqual(lossyFile.dataSet.string(for: .lossyImageCompressionMethod), "ISO_15444_1")
        XCTAssertNotEqual(lossyFile.dataSet.string(for: .sopInstanceUID), originalSOP)
        XCTAssertTrue((lossyFile.dataSet.string(for: .imageType) ?? "").hasPrefix("DERIVED"))

        for registry in [swiftRegistry, CodecRegistry.j2kSwiftRollback] {
            let decodedFrames = try extractLogicalGrayscaleSamples(from: lossyFile, codecRegistry: registry)
            for (orig, dec) in zip([frame0, frame1], decodedFrames) {
                let mse = zip(orig, dec).reduce(0.0) { acc, pair in
                    let diff = Double(pair.0 - pair.1)
                    return acc + diff * diff
                } / Double(orig.count)
                let psnr = mse == 0 ? 99.0 : (10.0 * log10((65535.0 * 65535.0) / mse))
                XCTAssertGreaterThanOrEqual(
                    psnr,
                    CompressionQuality.high.expectedMinPSNRDb,
                    "Lossy .91 PSNR (\(psnr) dB) fell below expectedMinPSNRDb (\(CompressionQuality.high.expectedMinPSNRDb) dB)"
                )
            }
        }
    }

    // MARK: - 4. Application Callers, Concurrent Provider Isolation & Explicit Rollback

    func testApplicationCallersConcurrentOperationPinningAndExplicitRollback() async throws {
        let rows = 16
        let columns = 16
        let frames: [[Int]] = (0..<4).map { f in
            (0..<(rows * columns)).map { idx in (idx * 13 + f * 97) & 0x0FFF }
        }
        let nativePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: frames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: false
        )

        let collector = SwiftJ2KTelemetryCollector()
        let swiftRegistry = CodecRegistry.swiftJ2K(options: SwiftJ2KProviderOptions(collector: collector))
        let rollbackRegistry = CodecRegistry.j2kSwiftRollback

        let encodedBytes = try CompressionManager(codecRegistry: swiftRegistry)
            .compressData(nativePart10, codec: "htj2k-lossless-only", quality: nil)
        let dicomFile = try DICOMFile.read(from: encodedBytes, options: .init(strictEncapsulation: true))

        // Exercise DICOMFile.alignedPixelData and DICOMFile.pixelDataParallel
        let aligned0 = try XCTUnwrap(dicomFile.alignedPixelData(frame: 0, codecRegistry: swiftRegistry))
        let regular0 = try XCTUnwrap(dicomFile.pixelData(frame: 0, codecRegistry: swiftRegistry))
        XCTAssertEqual(aligned0.data, regular0.data)

        let parallelDecoded = try await dicomFile.pixelDataParallel(codecRegistry: swiftRegistry)
        XCTAssertEqual(parallelDecoded.descriptor.numberOfFrames, 4)
        for f in 0..<4 {
            XCTAssertNotNil(parallelDecoded.frameData(at: f))
        }

        // Concurrent in-flight SwiftJ2K operations interleaved with explicit J2KSwift rollback operations
        // (bounded to 4 concurrent cooperative-pool callers so synchronous semaphore waits never starve
        // Swift's cooperative pool for `@concurrent` codec work)
        try await withThrowingTaskGroup(of: (CodecProviderID?, [[Int]]).self) { group in
            let maxConcurrentCallers = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
            var nextIndex = 0
            var swiftCount = 0
            var rollbackCount = 0

            func enqueueNext() {
                guard nextIndex < 16 else { return }
                let i = nextIndex
                nextIndex += 1
                let useRollback = (i % 2 == 1)
                let chosenRegistry = useRollback ? rollbackRegistry : swiftRegistry
                group.addTask {
                    let (_, metrics) = try CompressionManager(codecRegistry: chosenRegistry)
                        .compressDataWithMetrics(nativePart10, codec: "jpeg2000-lossless-only", quality: nil)
                    let samples = try Self.extractLogicalGrayscaleSamples(from: dicomFile, codecRegistry: chosenRegistry)
                    return (metrics.resolvedEncodeProviderID, samples)
                }
            }

            for _ in 0..<maxConcurrentCallers {
                enqueueNext()
            }
            while let (providerID, decodedSamples) = try await group.next() {
                XCTAssertEqual(decodedSamples, frames)
                if providerID == .swiftJ2K {
                    swiftCount += 1
                } else if providerID == .j2kSwift {
                    rollbackCount += 1
                } else {
                    XCTFail("Unexpected provider ID: \(String(describing: providerID))")
                }
                enqueueNext()
            }
            XCTAssertEqual(swiftCount, 8)
            XCTAssertEqual(rollbackCount, 8)
        }
    }

    // MARK: - 5. Pre-Execution Capability Refusals, Fallback Policy, Resource Limits, Deadlines & Cancellation

    func testUnsupportedCapabilitiesRefuseBeforeExecutionOrPreselectPredecessor() throws {
        let rows = 16
        let columns = 16
        let frames = [(0..<(rows * columns)).map { $0 & 0x0FFF }]
        let nativePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: frames,
            bitsAllocated: 16,
            bitsStored: 12,
            isSigned: false
        )
        let nativeFile = try DICOMFile.read(from: nativePart10)

        let collector = SwiftJ2KTelemetryCollector()
        let strictRegistry = CodecRegistry.swiftJ2K(
            options: SwiftJ2KProviderOptions(collector: collector),
            fallbackPolicy: .strict
        )
        let fallbackRegistry = CodecRegistry.swiftJ2K(
            options: SwiftJ2KProviderOptions(collector: collector),
            fallbackPolicy: .preselectPredecessorOnUnsupportedCapability
        )

        // 1. Lossy HTJ2K (.203) refused BEFORE execution under .strict
        collector.reset()
        XCTAssertThrowsError(
            try DICOMConverter.convertToDICOM(
                dicomFile: nativeFile,
                to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding("htj2k-lossy")),
                stripPrivate: false,
                codecRegistry: strictRegistry
            )
        )
        XCTAssertTrue(collector.records.isEmpty, "SwiftJ2K must not start executing on unsupported lossy .203")

        // Under .preselectPredecessorOnUnsupportedCapability, .j2kSwift is preselected BEFORE execution
        let preselectedLossyHT = try DICOMConverter.convertToDICOM(
            dicomFile: nativeFile,
            to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding("htj2k-lossy")),
            stripPrivate: false,
            codecRegistry: fallbackRegistry
        )
        XCTAssertEqual(preselectedLossyHT.resolvedEncodeProviderID, .j2kSwift)
        XCTAssertTrue(collector.records.isEmpty, "Preselected predecessor must run without touching SwiftJ2K")

        // 2. Forced .metal and .accelerate backends refused BEFORE execution under .strict, preselected under fallback
        for forcedBackend: CodecBackendPreference in [.metal, .accelerate] {
            collector.reset()
            XCTAssertThrowsError(
                try CompressionManager(codecRegistry: strictRegistry)
                    .compressDataWithMetrics(nativePart10, codec: "jpeg2000-lossless-only", quality: nil, backend: forcedBackend)
            )
            XCTAssertTrue(collector.records.isEmpty)

            let (_, fallbackMetrics) = try CompressionManager(codecRegistry: fallbackRegistry)
                .compressDataWithMetrics(nativePart10, codec: "jpeg2000-lossless-only", quality: nil, backend: forcedBackend)
            XCTAssertEqual(fallbackMetrics.resolvedEncodeProviderID, .j2kSwift)
            XCTAssertTrue(collector.records.isEmpty)
        }

        // 3. Part 2 (.92 / .93) encode refused before execution
        XCTAssertThrowsError(
            try DICOMConverter.convertToDICOM(
                dicomFile: nativeFile,
                to: try XCTUnwrap(DICOMConverter.resolveTargetEncoding("jpeg2000-part2-lossless-only")),
                stripPrivate: false,
                codecRegistry: strictRegistry
            )
        )
    }

    func testExecutionFailuresNeverRetryOnPredecessorAndRespectLimitsDeadlineAndCancellation() async throws {
        let rows = 32
        let columns = 32
        let frames = [(0..<(rows * columns)).map { ($0 * 73) & 0xFFFF }]
        let nativePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: frames,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )

        let validEncoded = try CompressionManager(codecRegistry: .swiftJ2K())
            .compressData(nativePart10, codec: "jpeg2000-lossless-only", quality: nil)
        let validFile = try DICOMFile.read(from: validEncoded)
        let validCodestream = try XCTUnwrap(validFile.dataSet[.pixelData]?.encapsulatedFragments?.first)
        let descriptor = PixelDataDescriptor(
            rows: rows,
            columns: columns,
            numberOfFrames: 1,
            bitsAllocated: 16,
            bitsStored: 16,
            highBit: 15,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2,
            planarConfiguration: 0
        )

        // 1. Corrupt codestream fails closed even when fallbackPolicy == .preselectPredecessorOnUnsupportedCapability
        var corruptDataSet = validFile.dataSet
        let truncated = Data(validCodestream.prefix(12))
        corruptDataSet[.pixelData] = DataElement(
            tag: .pixelData,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [truncated],
            encapsulatedOffsetTable: [0]
        )
        let corruptFile = DICOMFile(fileMetaInformation: validFile.fileMetaInformation, dataSet: corruptDataSet)
        let fallbackRegistry = CodecRegistry.swiftJ2K(fallbackPolicy: .preselectPredecessorOnUnsupportedCapability)
        XCTAssertThrowsError(
            try DICOMConverter.convertToDICOM(
                dicomFile: corruptFile,
                to: .init(transferSyntax: .explicitVRLittleEndian, intent: .notApplicable),
                stripPrivate: false,
                codecRegistry: fallbackRegistry
            )
        )

        // 2. Irreversible 9/7 codestream stuffed under lossless-only .90 is refused
        let lossy91 = try CompressionManager(codecRegistry: .swiftJ2K())
            .compressData(nativePart10, codec: "jpeg2000-lossy", quality: .high)
        let lossy91Stream = try XCTUnwrap(DICOMFile.read(from: lossy91).dataSet[.pixelData]?.encapsulatedFragments?.first)
        let lossless90Decoder = SwiftJ2KDICOMCodec(decodingTransferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
        XCTAssertThrowsError(try lossless90Decoder.decodeFrame(lossy91Stream, descriptor: descriptor, frameIndex: 0))

        // 3. Finite ResourceLimits refusal (tiny compressed/workspace ceiling) fails with DICOMError.limitExceeded without fallback
        let tinyLimits = try ResourceLimits(
            maximumCompressedBytes: 64,
            maximumDecodedBytes: 64 << 10,
            maximumWorkspaceBytes: 256,
            maximumPixels: 16 << 20,
            maximumDimension: 65_535,
            maximumFrames: 1,
            maximumMetadataBytes: 4096,
            maximumICCBytes: 4096,
            maximumNestingDepth: 8,
            maximumWorkers: 1,
            deadlineSeconds: 5.0,
            maximumMemoryBytes: 128 << 10
        )
        let tinyRegistry = CodecRegistry.swiftJ2K(
            options: SwiftJ2KProviderOptions(resourceLimits: tinyLimits),
            fallbackPolicy: .preselectPredecessorOnUnsupportedCapability
        )
        XCTAssertThrowsError(
            try CompressionManager(codecRegistry: tinyRegistry)
                .decompressData(validEncoded, syntax: .explicitVRLittleEndian)
        ) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected DICOMError.limitExceeded, got \(error)")
            }
        }
        XCTAssertThrowsError(
            try DICOMConverter.convertToDICOM(
                dicomFile: validFile,
                to: .init(transferSyntax: .explicitVRLittleEndian, intent: .notApplicable),
                stripPrivate: false,
                codecRegistry: tinyRegistry
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Resource limit exceeded"), "Unexpected error: \(error)")
        }

        // 4. Finite deadline refusal on large frame joins cleanly within bounded time
        let largeRows = 256
        let largeCols = 256
        let largeFrame = [(0..<(largeRows * largeCols)).map { ($0 * 4099 + ($0 >> 3)) & 0xFFFF }]
        let largePart10 = try makeGrayscalePart10(
            rows: largeRows,
            columns: largeCols,
            frames: largeFrame,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )
        let expiredLimits = try ResourceLimits(
            maximumCompressedBytes: 16 << 20,
            maximumDecodedBytes: 16 << 20,
            maximumWorkspaceBytes: 64 << 20,
            maximumPixels: 4 << 20,
            maximumDimension: 65_535,
            maximumFrames: 1,
            maximumMetadataBytes: 65_536,
            maximumICCBytes: 65_536,
            maximumNestingDepth: 8,
            maximumWorkers: 1,
            deadlineSeconds: 1e-7,
            maximumMemoryBytes: 96 << 20
        )
        let deadlineRegistry = CodecRegistry.swiftJ2K(
            options: SwiftJ2KProviderOptions(resourceLimits: expiredLimits, joinGraceSeconds: 1.0),
            fallbackPolicy: .preselectPredecessorOnUnsupportedCapability
        )
        let start = ContinuousClock.now
        XCTAssertThrowsError(
            try CompressionManager(codecRegistry: deadlineRegistry)
                .compressData(largePart10, codec: "jpeg2000-lossless-only", quality: nil)
        ) { error in
            guard case DICOMError.limitExceeded = error else {
                return XCTFail("Expected DICOMError.limitExceeded on deadline expiry, got \(error)")
            }
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, 5.0)

        // 5. Cooperative Task cancellation propagates CancellationError cleanly
        let preCancelledTask = Task { () throws -> Data in
            withUnsafeCurrentTask { $0?.cancel() }
            return try CompressionManager(codecRegistry: .swiftJ2K())
                .compressData(largePart10, codec: "htj2k-lossless-only", quality: nil)
        }
        do {
            _ = try await preCancelledTask.value
            XCTFail("Expected pre-cancelled Task to throw CancellationError")
        } catch is CancellationError {
            // Expected clean cancellation
        }
    }

    // MARK: - 6. CLI Executable End-to-End & Telemetry Receipt

    #if os(macOS)
    func testCLIExecutableCompressConvertDecompressAndRollback() throws {
        let scratch = try makeScratchDirectory(prefix: "m12-cli")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let rows = 32
        let columns = 32
        let frames: [[Int]] = (0..<2).map { f in
            (0..<(rows * columns)).map { idx in (idx * 29 + f * 313) & 0xFFFF }
        }
        let sourcePart10 = try makeGrayscalePart10(
            rows: rows,
            columns: columns,
            frames: frames,
            bitsAllocated: 16,
            bitsStored: 16,
            isSigned: false
        )

        let inputURL = scratch.appendingPathComponent("input.part10")
        let j2kURL = scratch.appendingPathComponent("j2k90.part10")
        let htj2kURL = scratch.appendingPathComponent("htj2k201.part10")
        let decompURL = scratch.appendingPathComponent("decomp.part10")
        let rollbackURL = scratch.appendingPathComponent("rollback.part10")
        let compressReportURL = scratch.appendingPathComponent("compress-report.json")
        let convertReportURL = scratch.appendingPathComponent("convert-report.json")
        let rollbackReportURL = scratch.appendingPathComponent("rollback-report.json")

        try sourcePart10.write(to: inputURL)

        let binURL = try locateCLIBinary()

        // 1. Compress with SwiftJ2K
        try runProcess(binURL, arguments: [
            "compress", inputURL.path, j2kURL.path,
            "--codec", "jpeg2000-lossless-only",
            "--provider", "swiftj2k",
            "--report-json", compressReportURL.path
        ])
        let compressReport = try JSONSerialization.jsonObject(with: Data(contentsOf: compressReportURL)) as? [String: Any]
        XCTAssertEqual(compressReport?["resolvedEncodeProviderID"] as? String, "swiftj2k")

        // 2. Convert .90 -> .201 via compressed-domain SwiftJ2K.Transcoder
        try runProcess(binURL, arguments: [
            "convert", j2kURL.path, htj2kURL.path,
            "--transfer-syntax", "htj2k-lossless-only",
            "--provider", "swiftj2k",
            "--report-json", convertReportURL.path
        ])
        let convertReport = try JSONSerialization.jsonObject(with: Data(contentsOf: convertReportURL)) as? [String: Any]
        XCTAssertEqual(convertReport?["resolvedTranscodeProviderID"] as? String, "swiftj2k")
        let ops = convertReport?["swiftJ2KOperations"] as? [[String: Any]]
        XCTAssertEqual(ops?.count, 2)
        XCTAssertTrue(ops?.allSatisfy { ($0["pixelAllocationCount"] as? Int) == 0 && ($0["backend"] as? String) == "scalarCPU" } == true)

        // 3. Decompress with SwiftJ2K
        try runProcess(binURL, arguments: [
            "decompress", htj2kURL.path, decompURL.path,
            "--provider", "swiftj2k"
        ])
        let decompFile = try DICOMFile.read(from: Data(contentsOf: decompURL))
        XCTAssertEqual(try extractLogicalGrayscaleSamples(from: decompFile, codecRegistry: .j2kSwiftRollback), frames)

        // 4. Rollback to predecessor J2KSwift via CLI --provider j2kswift
        try runProcess(binURL, arguments: [
            "compress", inputURL.path, rollbackURL.path,
            "--codec", "htj2k-lossless-only",
            "--provider", "j2kswift",
            "--report-json", rollbackReportURL.path
        ])
        let rollbackReport = try JSONSerialization.jsonObject(with: Data(contentsOf: rollbackReportURL)) as? [String: Any]
        XCTAssertEqual(rollbackReport?["resolvedEncodeProviderID"] as? String, "j2kswift")
        XCTAssertEqual((rollbackReport?["swiftJ2KOperations"] as? [Any])?.count, 0)

        if let receiptPath = ProcessInfo.processInfo.environment["SWIFTJ2K_M12_TELEMETRY_JSON"], !receiptPath.isEmpty {
            let summary: [String: Any] = [
                "compress_report": compressReport ?? [:],
                "convert_report": convertReport ?? [:],
                "rollback_report": rollbackReport ?? [:]
            ]
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: receiptPath))
        }
    }

    private func locateCLIBinary() throws -> URL {
        if let envBin = ProcessInfo.processInfo.environment["SWIFTJ2K_M12_CLI_BIN"], !envBin.isEmpty {
            let url = URL(fileURLWithPath: envBin)
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path), "Missing CLI binary at \(url.path)")
            return url
        }
        // SwiftPM places built executables alongside the .xctest bundle inside .build/<triple>/debug/
        let bundleURL = Bundle(for: Self.self).bundleURL
        let buildDir = bundleURL.deletingLastPathComponent()
        let candidate = buildDir.appendingPathComponent("dicom-swiftj2k")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw XCTSkip("dicom-swiftj2k binary not found next to test bundle at \(candidate.path)")
    }

    private func runProcess(_ executable: URL, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("dicom-swiftj2k \(arguments.joined(separator: " ")) failed with status \(proc.terminationStatus): \(errText)")
            return
        }
    }
    #endif
}
