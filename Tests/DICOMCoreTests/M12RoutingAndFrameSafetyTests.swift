import XCTest
import Foundation
import Synchronization
import Dispatch
@testable import DICOMCore
@testable import DICOMKit

final class M12RoutingAndFrameSafetyTests: XCTestCase {

    // MARK: - Test Doubles

    private final class InvocationRecorder: Sendable {
        struct State: Sendable {
            var decodedFrames: [(provider: CodecProviderID, frameIndex: Int, bytes: Data)] = []
            var encodedCalls: [CodecProviderID] = []
            var transcodedFrames: [(provider: CodecProviderID, bytes: Data)] = []
        }

        private let mutex = Mutex(State())

        func recordDecode(provider: CodecProviderID, frameIndex: Int, bytes: Data) {
            mutex.withLock { $0.decodedFrames.append((provider, frameIndex, bytes)) }
        }

        func recordEncode(provider: CodecProviderID) {
            mutex.withLock { $0.encodedCalls.append(provider) }
        }

        func recordTranscode(provider: CodecProviderID, bytes: Data) {
            mutex.withLock { $0.transcodedFrames.append((provider, bytes)) }
        }

        var snapshot: State {
            mutex.withLock { $0 }
        }
    }

    private struct MockFailure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct MockJ2KCodec: ImageCodec, ImageEncoder, DecodeBackendConfigurableCodec, Sendable {
        static let supportedTransferSyntaxes: [String] = J2KSwiftCodec.supportedTransferSyntaxes
        static let supportedEncodingTransferSyntaxes: [String] = J2KSwiftCodec.supportedEncodingTransferSyntaxes

        let providerID: CodecProviderID
        let recorder: InvocationRecorder
        let canDecodeDescriptor: @Sendable (PixelDataDescriptor) -> Bool
        let canEncodeConfig: @Sendable (CompressionConfiguration, PixelDataDescriptor) -> Bool
        let decodeAction: @Sendable (Data, PixelDataDescriptor, Int) throws -> Data
        let encodeAction: @Sendable (Data, PixelDataDescriptor, CompressionConfiguration) throws -> [Data]

        func withDecodeBackend(_ backend: CodecBackend?) -> any ImageCodec {
            self
        }

        func canDecode(_ descriptor: PixelDataDescriptor) -> Bool {
            canDecodeDescriptor(descriptor)
        }

        func decodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int) throws -> Data {
            recorder.recordDecode(provider: providerID, frameIndex: frameIndex, bytes: frameData)
            return try decodeAction(frameData, descriptor, frameIndex)
        }

        func canEncode(with configuration: CompressionConfiguration, descriptor: PixelDataDescriptor) -> Bool {
            canEncodeConfig(configuration, descriptor)
        }

        func encode(_ pixelData: Data, descriptor: PixelDataDescriptor, configuration: CompressionConfiguration) throws -> [Data] {
            recorder.recordEncode(provider: providerID)
            return try encodeAction(pixelData, descriptor, configuration)
        }

        func encodeFrame(_ frameData: Data, descriptor: PixelDataDescriptor, frameIndex: Int, configuration: CompressionConfiguration) throws -> Data {
            let singleDescriptor = PixelDataDescriptor(
                rows: descriptor.rows,
                columns: descriptor.columns,
                numberOfFrames: 1,
                bitsAllocated: descriptor.bitsAllocated,
                bitsStored: descriptor.bitsStored,
                highBit: descriptor.highBit,
                isSigned: descriptor.isSigned,
                samplesPerPixel: descriptor.samplesPerPixel,
                photometricInterpretation: descriptor.photometricInterpretation,
                planarConfiguration: descriptor.planarConfiguration
            )
            let frames = try encode(frameData, descriptor: singleDescriptor, configuration: configuration)
            guard let first = frames.first else {
                throw MockFailure(message: "Mock encoder produced no frame")
            }
            return first
        }
    }

    private struct MockJ2KTranscoder: J2KCompressedDomainTranscoder, Sendable {
        let providerID: CodecProviderID
        let recorder: InvocationRecorder
        let canTranscodeFn: @Sendable (String, String, PixelDataDescriptor?) -> Bool
        let transcodeFn: @Sendable (Data, String, String, PixelDataDescriptor?) throws -> Data

        func canTranscode(from sourceTransferSyntaxUID: String, to targetTransferSyntaxUID: String, descriptor: PixelDataDescriptor?) -> Bool {
            canTranscodeFn(sourceTransferSyntaxUID, targetTransferSyntaxUID, descriptor)
        }

        func transcodeCodestream(_ codestream: Data, from sourceTransferSyntaxUID: String, to targetTransferSyntaxUID: String, descriptor: PixelDataDescriptor?) throws -> Data {
            recorder.recordTranscode(provider: providerID, bytes: codestream)
            return try transcodeFn(codestream, sourceTransferSyntaxUID, targetTransferSyntaxUID, descriptor)
        }
    }

    private func provider(_ codec: MockJ2KCodec,
                          transcoder: (any J2KCompressedDomainTranscoder)? = nil) -> J2KCodecProvider {
        J2KCodecProvider(
            providerID: codec.providerID,
            supportedDecodingTransferSyntaxUIDs: [TransferSyntax.jpeg2000Lossless.uid, TransferSyntax.htj2kLossless.uid],
            supportedEncodingTransferSyntaxUIDs: [TransferSyntax.jpeg2000Lossless.uid, TransferSyntax.htj2kLossless.uid],
            makeDecoder: { _ in codec }, makeEncoder: { _ in codec },
            canDecodeProfile: { _, descriptor, _ in descriptor.map(codec.canDecodeDescriptor) ?? true },
            canEncodeProfile: { _, config, descriptor in codec.canEncode(with: config, descriptor: descriptor) },
            compressedDomainTranscoder: transcoder
        )
    }

    private func parse(_ data: Data, syntax: TransferSyntax) throws -> DataSet {
        var parser = DICOMParser(data: data)
        return try parser.parseDataSet(startOffset: 0, transferSyntaxUID: syntax.uid)
    }

    // MARK: - Dataset Builders

    private func makeNativeDataSet(
        rows: Int = 8,
        cols: Int = 8,
        frames: Int = 2,
        bitsAllocated: Int = 16,
        bitsStored: Int = 16,
        isSigned: Bool = false
    ) -> DataSet {
        var ds = DataSet()
        ds.setString("1.2.840.10008.5.1.4.1.1.2", for: .sopClassUID, vr: .UI)
        ds.setString("1.2.3.4.5.6.7", for: .sopInstanceUID, vr: .UI)
        ds.setUInt16(1, for: .samplesPerPixel)
        ds.setString("MONOCHROME2", for: .photometricInterpretation, vr: .CS)
        if frames > 1 {
            ds.setString("\(frames)", for: .numberOfFrames, vr: .IS)
        }
        ds.setUInt16(UInt16(rows), for: .rows)
        ds.setUInt16(UInt16(cols), for: .columns)
        ds.setUInt16(UInt16(bitsAllocated), for: .bitsAllocated)
        ds.setUInt16(UInt16(bitsStored), for: .bitsStored)
        ds.setUInt16(UInt16(bitsStored - 1), for: .highBit)
        ds.setUInt16(isSigned ? 1 : 0, for: .pixelRepresentation)

        let bytesPerSample = bitsAllocated / 8
        var pixels = Data(capacity: rows * cols * frames * bytesPerSample)
        for f in 0..<frames {
            for i in 0..<(rows * cols) {
                let value = UInt16((f * 257 + i * 17) & 0xFFFF)
                if bytesPerSample == 2 {
                    pixels.append(UInt8(value & 0xFF))
                    pixels.append(UInt8(value >> 8))
                } else {
                    pixels.append(UInt8(value & 0xFF))
                }
            }
        }
        ds[.pixelData] = DataElement(
            tag: .pixelData,
            vr: bitsAllocated > 8 ? .OW : .OB,
            length: UInt32(pixels.count),
            valueData: pixels
        )
        return ds
    }

    private func makeUInt64LEData(_ values: [UInt64]) -> Data {
        var data = Data(capacity: values.count * 8)
        for value in values {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }

    private enum ExecutionRefusal: CaseIterable, Sendable {
        case malformed, exhausted, cancelled

        func raise() throws -> Never {
            switch self {
            case .malformed: throw DICOMError.parsingFailed("injected malformed frame")
            case .exhausted: throw DICOMError.limitExceeded("injected resource refusal")
            case .cancelled: throw CancellationError()
            }
        }

        func matches(_ error: Error) -> Bool {
            switch self {
            case .malformed:
                guard case .parsingFailed(let reason) = error as? DICOMError else { return false }
                return reason == "injected malformed frame"
            case .exhausted:
                guard case .limitExceeded(let reason) = error as? DICOMError else { return false }
                return reason == "injected resource refusal"
            case .cancelled:
                return error is CancellationError
            }
        }
    }

    private func failingCodec(_ recorder: InvocationRecorder, refusal: ExecutionRefusal) -> MockJ2KCodec {
        MockJ2KCodec(providerID: CodecProviderID(rawValue: "test.refusing"), recorder: recorder,
                     canDecodeDescriptor: { _ in true }, canEncodeConfig: { _, _ in true },
                     decodeAction: { _, _, _ in try refusal.raise() },
                     encodeAction: { _, _, _ in try refusal.raise() })
    }

    func testMalformedResourceAndCancellationFailuresPreserveSelectedProvider() throws {
        let native = makeNativeDataSet(rows: 8, cols: 8, frames: 2, bitsAllocated: 8, bitsStored: 8)
        let file = DICOMFile.create(dataSet: native)
        let encoded = try CompressionManager().compressData(try file.write(),
                                                            codec: "jpeg2000-lossless-only", quality: nil)
        let source = try DICOMFile.read(from: encoded).dataSet
        let sourceBytes = try source.writeChecked()
        let nativeBytes = try native.writeChecked()
        // The predecessor can decode these frames, so retrying after a primary failure
        // would change the outcome. Each operation must propagate its precise error.
        for refusal in ExecutionRefusal.allCases {
            let recorder = InvocationRecorder()
            let codec = failingCodec(recorder, refusal: refusal)
            let transcoder = MockJ2KTranscoder(
                providerID: codec.providerID, recorder: recorder, canTranscodeFn: { _, _, _ in true },
                transcodeFn: { _, _, _, _ in try refusal.raise() }
            )
            let registry = CodecRegistry(j2kProvider: provider(codec, transcoder: transcoder),
                                         j2kFallbackPolicy: .preselectPredecessorOnUnsupportedCapability)
            let converter = TransferSyntaxConverter(codecRegistry: registry)
            var dataSet = source
            XCTAssertThrowsError(try CompressionManager.decodePixelDataInPlace(
                dataSet: &dataSet, sourceSyntax: .jpeg2000Lossless, targetSyntax: .explicitVRLittleEndian,
                codecRegistry: registry
            )) { XCTAssertTrue(refusal.matches($0), String(describing: $0)) }
            XCTAssertThrowsError(try converter.transcode(dataSetData: nativeBytes, from: .explicitVRLittleEndian,
                                                        to: .jpeg2000Lossless)) {
                XCTAssertTrue(refusal.matches($0), String(describing: $0))
            }
            XCTAssertThrowsError(try converter.transcode(dataSetData: sourceBytes, from: .jpeg2000Lossless,
                                                        to: .htj2kLossless)) {
                XCTAssertTrue(refusal.matches($0), String(describing: $0))
            }
            XCTAssertEqual(recorder.snapshot.decodedFrames.map(\.frameIndex), [0])
            XCTAssertEqual(recorder.snapshot.encodedCalls, [codec.providerID])
            XCTAssertEqual(recorder.snapshot.transcodedFrames.count, 1)
        }
    }

    func testCompressedSyntaxRejectsNativePixelValueBeforeCodecInvocation() throws {
        let native = makeNativeDataSet(rows: 8, cols: 8, frames: 1, bitsAllocated: 8, bitsStored: 8)
        let rawBytes = try native.writeChecked()
        let recorder = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(recorder, refusal: .malformed)))
        let file = DICOMFile.create(dataSet: native, transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
        let converter = TransferSyntaxConverter(codecRegistry: registry)
        var dataSet = native
        XCTAssertThrowsError(try CompressionManager.decodePixelDataInPlace(
            dataSet: &dataSet, sourceSyntax: .jpeg2000Lossless, targetSyntax: .explicitVRLittleEndian,
            codecRegistry: registry
        ))
        XCTAssertThrowsError(try converter.transcode(dataSetData: rawBytes, from: .jpeg2000Lossless,
                                                    to: .explicitVRLittleEndian))
        XCTAssertThrowsError(try file.pixelData(frame: 0, codecRegistry: registry))
        XCTAssertTrue(recorder.snapshot.decodedFrames.isEmpty)
    }

    func testOversizedNativeOutputIsRejectedBeforeDecoderInvocation() throws {
        var huge = makeNativeDataSet(rows: 1, cols: 1, frames: 1, bitsAllocated: 16, bitsStored: 16)
        huge.setUInt16(UInt16.max, for: .rows)
        huge.setUInt16(UInt16.max, for: .columns)
        huge[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                                       encapsulatedFragments: [Data([0, 0])], encapsulatedOffsetTable: [])
        let encoded = try huge.writeChecked()
        let recorder = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(recorder, refusal: .exhausted)))
        XCTAssertThrowsError(try CompressionManager.decodePixelDataInPlace(
            dataSet: &huge, sourceSyntax: .jpeg2000Lossless, targetSyntax: .explicitVRLittleEndian,
            codecRegistry: registry
        ))
        XCTAssertThrowsError(try TransferSyntaxConverter(codecRegistry: registry)
            .transcode(dataSetData: encoded, from: .jpeg2000Lossless, to: .explicitVRLittleEndian))
        XCTAssertTrue(recorder.snapshot.decodedFrames.isEmpty)
    }

    func testTinyNativePixelValueWithHugeFrameCountRefusesBeforeEncode() throws {
        var native = makeNativeDataSet(rows: 1, cols: 1, frames: 1, bitsAllocated: 16, bitsStored: 16)
        // The expected native value would consume 2 GB. Only two actual bytes are present.
        native.setString("1000000000", for: .numberOfFrames, vr: .IS)
        let recorder = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(recorder, refusal: .malformed)))
        let fileBytes = try DICOMFile.create(dataSet: native).write()
        XCTAssertThrowsError(try CompressionManager(codecRegistry: registry).compressData(
            fileBytes, codec: "jpeg2000-lossless-only", quality: nil
        ))
        XCTAssertThrowsError(try TransferSyntaxConverter(codecRegistry: registry).transcode(
            dataSetData: native.writeChecked(), from: .explicitVRLittleEndian, to: .jpeg2000Lossless
        ))
        XCTAssertTrue(recorder.snapshot.encodedCalls.isEmpty)
    }

    func testMetadataOnlyTranscodeReportsNoProviderExecution() throws {
        var metadata = makeNativeDataSet(rows: 4, cols: 4, frames: 1)
        metadata[.pixelData] = nil
        let source = try metadata.writeChecked()
        let recorder = InvocationRecorder()
        let codec = failingCodec(recorder, refusal: .malformed)
        let transcoder = MockJ2KTranscoder(
            providerID: codec.providerID, recorder: recorder, canTranscodeFn: { _, _, _ in true },
            transcodeFn: { _, _, _, _ in try ExecutionRefusal.malformed.raise() }
        )
        let converter = TransferSyntaxConverter(codecRegistry: CodecRegistry(
            j2kProvider: provider(codec, transcoder: transcoder)
        ))
        let pairs: [(TransferSyntax, TransferSyntax)] = [
            (.explicitVRLittleEndian, .jpeg2000Lossless),
            (.jpeg2000Lossless, .explicitVRLittleEndian),
            (.jpeg2000Lossless, .htj2kLossless)
        ]
        for (sourceSyntax, targetSyntax) in pairs {
            let result = try converter.transcode(dataSetData: source, from: sourceSyntax, to: targetSyntax)
            XCTAssertNil(result.resolvedEncodeProviderID)
            XCTAssertNil(result.resolvedDecodeProviderID)
            XCTAssertNil(result.resolvedTranscodeProviderID)
            let parsed = try parse(result.data, syntax: targetSyntax)
            XCTAssertNil(parsed[.pixelData])
            XCTAssertEqual(parsed.string(for: .sopInstanceUID), metadata.string(for: .sopInstanceUID))
        }
        XCTAssertTrue(recorder.snapshot.encodedCalls.isEmpty)
        XCTAssertTrue(recorder.snapshot.decodedFrames.isEmpty)
        XCTAssertTrue(recorder.snapshot.transcodedFrames.isEmpty)
    }

    func testMalformedWireFragmentItemLengthsRefuseBeforeDecode() throws {
        var attributes = makeNativeDataSet(rows: 4, cols: 4, frames: 1, bitsAllocated: 8, bitsStored: 8)
        attributes[.pixelData] = nil
        let datasetPrefix = try attributes.writeChecked()
        let filePrefix = try DICOMFile.create(dataSet: attributes, transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
            .write()
        let recorder = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(recorder, refusal: .malformed)))
        let manager = CompressionManager(codecRegistry: registry)
        let converter = TransferSyntaxConverter(codecRegistry: registry)
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        for length in [0, 3] {
            var wire = writer.serializeElementHeader(tag: .pixelData, vr: .OB, length: UInt32.max)
            wire.append(writer.serializeTag(.item))
            wire.append(writer.serializeUInt32(0)) // empty Basic Offset Table
            wire.append(writer.serializeTag(.item))
            wire.append(writer.serializeUInt32(UInt32(length)))
            wire.append(Data(repeating: 1, count: length))
            wire.append(writer.serializeTag(.sequenceDelimitationItem))
            wire.append(writer.serializeUInt32(0))
            XCTAssertThrowsError(try converter.transcode(dataSetData: datasetPrefix + wire,
                                                        from: .jpeg2000Lossless, to: .explicitVRLittleEndian))
            XCTAssertThrowsError(try manager.decompressData(filePrefix + wire, syntax: .explicitVRLittleEndian))
            XCTAssertTrue(recorder.snapshot.decodedFrames.isEmpty)
        }
    }

    func testJoinedFrameHonoursExactCompressedInputCap() throws {
        let descriptor = try makeNativeDataSet(rows: 2, cols: 2, frames: 1).tryPixelDataDescriptor()
        let encapsulated = EncapsulatedPixelData(offsetTable: [], fragments: [Data([1, 2]), Data([3, 4, 5, 6])],
                                                descriptor: descriptor)
        let index = try XCTUnwrap(encapsulated.makeFrameIndex())
        XCTAssertNil(encapsulated.frameData(at: 0, using: index, maximumBytes: 5))
        XCTAssertEqual(encapsulated.frameData(at: 0, using: index, maximumBytes: 6), Data([1, 2, 3, 4, 5, 6]))
    }

    func testSharedOversizedFrameRefusesBeforeDICOMFileCodec() throws {
        var attributes = makeNativeDataSet(rows: 1, cols: 1, frames: 1, bitsAllocated: 8, bitsStored: 8)
        // Reuse one backing. The logical frame is one fragment beyond the encoded admission limit.
        let piece = Data(repeating: 0xda, count: 1 << 20)
        let count = PixelDecodeLimits.default.maximumEncodedBytes / piece.count + 1
        attributes[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
            encapsulatedFragments: Array(repeating: piece, count: count), encapsulatedOffsetTable: [])
        let file = DICOMFile.create(dataSet: attributes, transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
        let calls = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(calls, refusal: .malformed)))
        XCTAssertThrowsError(try file.pixelData(frame: 0, codecRegistry: registry))
        XCTAssertThrowsError(try file.tryPixelData(codecRegistry: registry))
        XCTAssertThrowsError(try MultiframePixelAssembler.extractFrame(from: file, frame: 0, handling: .preserve))
        XCTAssertTrue(calls.snapshot.decodedFrames.isEmpty)
    }

    func testPreserveNativeFrameRejectsOverflowAndKeepsPackedBytes() throws {
        var attributes = makeNativeDataSet(rows: 1, cols: 1, frames: 1)
        // These IS/US values are representable individually. The frame's byte
        // offset exceeds Int.max, while the actual Pixel Data has only two bytes.
        attributes.setUInt16(65535, for: .rows)
        attributes.setUInt16(65528, for: .columns)
        attributes.setString("100000000000", for: .numberOfFrames, vr: .IS)
        let frame = 99_999_999_999
        for width: UInt16 in [1, 16] {
            attributes.setUInt16(width, for: .bitsAllocated)
            attributes.setUInt16(width, for: .bitsStored)
            attributes.setUInt16(width - 1, for: .highBit)
            let file = DICOMFile.create(dataSet: attributes)
            XCTAssertThrowsError(try MultiframePixelAssembler.extractFrame(from: file, frame: frame, handling: .preserve)) {
                guard case .frameExtractionFailed(let refusedFrame) = $0 as? MultiframePixelError else {
                    return XCTFail("Expected checked frame offset refusal, got \($0)")
                }
                XCTAssertEqual(refusedFrame, frame)
            }
        }

        attributes.setUInt16(1, for: .rows)
        attributes.setUInt16(8, for: .columns)
        attributes.setUInt16(1, for: .bitsAllocated)
        attributes.setUInt16(1, for: .bitsStored)
        attributes.setUInt16(0, for: .highBit)
        attributes.setString("2", for: .numberOfFrames, vr: .IS)
        attributes[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: 2, valueData: Data([0xa5, 0x3c]))
        let second = try MultiframePixelAssembler.extractFrame(from: DICOMFile.create(dataSet: attributes),
                                                               frame: 1, handling: .preserve)
        guard case .native(let bytes) = second.storage else { return XCTFail("Expected native packed frame") }
        XCTAssertEqual(bytes, Data([0x3c]))
        attributes.setUInt16(7, for: .columns)
        XCTAssertThrowsError(try MultiframePixelAssembler.extractFrame(from: DICOMFile.create(dataSet: attributes),
                                                                        frame: 1, handling: .preserve)) {
            guard case .unalignedSubBytePixels(let bits) = $0 as? MultiframePixelError else {
                return XCTFail("Expected packed frame alignment refusal, got \($0)")
            }
            XCTAssertEqual(bits, 7)
        }
    }

    func testAssembledFrameValueBoundsAndReplacementOffsets() throws {
        let descriptor = try makeNativeDataSet(rows: 1, cols: 3, frames: 1, bitsAllocated: 8, bitsStored: 8)
            .tryPixelDataDescriptor()
        let first = Data([1, 2, 3])
        let second = Data([4, 5, 6, 7])
        let sourceUID = TransferSyntax.jpeg2000Lossless.uid
        let a = FramePixelPayload(storage: .encapsulated(first), transferSyntaxUID: sourceUID, descriptor: descriptor)
        let b = FramePixelPayload(storage: .encapsulated(second), transferSyntaxUID: sourceUID, descriptor: descriptor)
        // 28 fixed bytes + 8 BOT bytes + two 12-byte padded items.
        XCTAssertThrowsError(try MultiframePixelAssembler.assemble([a, b], maximumBytes: 59))
        let encoded = try MultiframePixelAssembler.assemble([a, b], maximumBytes: 60).element
        XCTAssertEqual(encoded.encapsulatedOffsetTable, [0, 12])
        XCTAssertEqual(encoded.encapsulatedFragments, [first, second])

        var dataSet = DataSet(), meta = DataSet()
        dataSet[.extendedOffsetTable] = DataElement(tag: .extendedOffsetTable, vr: .OV, length: 8,
                                                   valueData: Data(repeating: 0, count: 8))
        dataSet[.extendedOffsetTableLengths] = DataElement(tag: .extendedOffsetTableLengths, vr: .OV, length: 8,
                                                          valueData: makeUInt64LEData([3]))
        dataSet[.pixelData] = encoded
        MultiframePixelAssembler.applyPixelDescription(a, to: &dataSet, fileMeta: &meta)
        XCTAssertNil(dataSet[.extendedOffsetTable])
        XCTAssertNil(dataSet[.extendedOffsetTableLengths])

        let native = FramePixelPayload(storage: .native(first), transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid,
                                       descriptor: descriptor)
        XCTAssertThrowsError(try MultiframePixelAssembler.assemble([native], maximumBytes: 3))
        let padded = try MultiframePixelAssembler.assemble([native], maximumBytes: 4).element
        XCTAssertEqual(padded.valueData, Data([1, 2, 3, 0]))
        XCTAssertEqual(padded.length, 4)
    }

    func testCheckedWriterPropagatesEncapsulationCapThroughNestedSequenceItems() throws {
        let pixel = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                                encapsulatedFragments: [Data(repeating: 1, count: 32)], encapsulatedOffsetTable: [])
        func sequence(_ child: DataElement) -> DataElement {
            DataElement(tag: .referencedSeriesSequence, vr: .SQ, length: UInt32.max, valueData: Data(),
                        sequenceItems: [SequenceItem(elements: [child])])
        }
        let nested = sequence(sequence(pixel))
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        XCTAssertThrowsError(try writer.serializeCheckedElement(nested, maxEncapsulatedBytes: 64)) {
            XCTAssertEqual($0 as? EncapsulatedOffsetBuildError,
                           .totalSerializedLengthOutOfBounds(totalBytes: 68, maximumAllowedBytes: 64))
        }
        XCTAssertEqual(try writer.serializeCheckedElement(nested, maxEncapsulatedBytes: 68),
                       writer.serializeElement(nested))
    }

    func testConverterRebuildsOffsetsWhenFrameLengthsChangeAndFinalFragmentNeedsPadding() throws {
        // The test provider treats the payloads as opaque. One complete frame spans two
        // fragments, with padding only at the end of the frame. The converter must hand
        // two complete payloads to the provider, and rebuild the BOT for new lengths.
        var ds = makeNativeDataSet(rows: 4, cols: 4, frames: 2, bitsAllocated: 8, bitsStored: 8)
        let fragments = [Data([1, 2]), Data([3, 4, 5]), Data([6, 7])]
        ds[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                                     encapsulatedFragments: fragments, encapsulatedOffsetTable: [0, 22])
        let recorder = InvocationRecorder()
        let codec = failingCodec(recorder, refusal: .malformed)
        let transcoder = MockJ2KTranscoder(
            providerID: codec.providerID, recorder: recorder, canTranscodeFn: { _, _, _ in true },
            transcodeFn: { bytes, _, _, _ in
                if bytes == Data([1, 2, 3, 4, 5, 0]) { return Data([9, 8, 7]) }
                if bytes == Data([6, 7]) { return Data([6, 5]) }
                throw MockFailure(message: "Provider received a partial or incorrectly padded frame")
            }
        )
        let registry = CodecRegistry(j2kProvider: provider(codec, transcoder: transcoder))
        let converted = try TransferSyntaxConverter(codecRegistry: registry)
            .transcode(dataSetData: ds.writeChecked(), from: .jpeg2000Lossless, to: .htj2kLossless)
        XCTAssertEqual(converted.resolvedTranscodeProviderID, codec.providerID)
        XCTAssertEqual(recorder.snapshot.transcodedFrames.map(\.bytes), [Data([1, 2, 3, 4, 5, 0]), Data([6, 7])])
        let result = try parse(converted.data, syntax: .htj2kLossless)
        let output = try XCTUnwrap(result.encapsulatedPixelData())
        XCTAssertEqual(output.offsetTable, [0, 12])
        XCTAssertEqual(output.fragments, [Data([9, 8, 7, 0]), Data([6, 5])])
        XCTAssertEqual(result.string(for: .sopInstanceUID), ds.string(for: .sopInstanceUID))
        XCTAssertEqual(result.uint16(for: .bitsStored), ds.uint16(for: .bitsStored))
    }

    // MARK: - 1. Immutable Per-Operation Provider Selection & Concurrent Rollback

    func testDefaultRegistryPreservesJ2KSwiftProviderAndImmutability() throws {
        XCTAssertEqual(CodecRegistry.shared.j2kProvider.providerID, .swiftJ2K)
        XCTAssertEqual(CodecRegistry.shared.j2kFallbackPolicy, .strict)

        let freshDefault = CodecRegistry()
        XCTAssertEqual(freshDefault.j2kProvider.providerID, .swiftJ2K)
    }

    func testPerOperationProviderSelectionAndConcurrentRollbackIsolation() async throws {
        let nativeDS = makeNativeDataSet(rows: 8, cols: 8, frames: 4, bitsAllocated: 8, bitsStored: 8)
        let nativeFile = DICOMFile.create(
            dataSet: nativeDS,
            transferSyntaxUID: TransferSyntax.explicitVRLittleEndian.uid
        )
        let compressedBytes = try CompressionManager().compressData(
            try nativeFile.write(),
            codec: "jpeg2000-lossless-only",
            quality: nil
        )
        let j2kFile = try DICOMFile.read(from: compressedBytes)
        let original = try XCTUnwrap(nativeDS[.pixelData]?.valueData)

        let recorder = InvocationRecorder()
        let customID = CodecProviderID(rawValue: "mock.successor")
        let predecessorCodec = J2KSwiftCodec()
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)

        let mockCodec = MockJ2KCodec(
            providerID: customID,
            recorder: recorder,
            canDecodeDescriptor: { _ in true },
            canEncodeConfig: { _, _ in true },
            decodeAction: { data, descriptor, frameIndex in
                if frameIndex == 0 {
                    entered.signal()
                    guard resume.wait(timeout: .now() + 20) == .success else {
                        throw MockFailure(message: "Timed out waiting for rollback operation")
                    }
                }
                return try predecessorCodec.decodeFrame(data, descriptor: descriptor, frameIndex: frameIndex)
            },
            encodeAction: { data, descriptor, config in
                try predecessorCodec.encode(data, descriptor: descriptor, configuration: config)
            }
        )
        let customProvider = provider(mockCodec)
        let customRegistry = CodecRegistry(j2kProvider: customProvider, j2kFallbackPolicy: .strict)
        let rollbackRegistry = CodecRegistry.shared

        // Hold the first custom frame so the rollback operation really overlaps the original.
        async let customParallel = j2kFile.pixelDataParallel(maxInFlightBytes: 64, codecRegistry: customRegistry)
        let didEnter = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success)
            }
        }
        XCTAssertTrue(didEnter)
        let rolledBack: PixelData
        do {
            rolledBack = try await j2kFile.pixelDataParallel(maxInFlightBytes: 64, codecRegistry: rollbackRegistry)
        } catch {
            resume.signal()
            throw error
        }
        resume.signal()
        let customResult = try await customParallel
        XCTAssertEqual(customResult.data, original)
        XCTAssertEqual(rolledBack.data, original)

        // All 4 frames of the custom operation must have executed on `customID`.
        let recorded = recorder.snapshot.decodedFrames
        XCTAssertEqual(recorded.count, 4)
        XCTAssertTrue(recorded.allSatisfy { $0.provider == customID })
        XCTAssertEqual(Set(recorded.map(\.frameIndex)), Set(0..<4))
    }

    // MARK: - 2. Pre-Execution Capability Fallback vs No-Retry on Runtime Failure

    func testPreExecutionCapabilityFallbackAndStrictRefusal() throws {
        let nativeDS = makeNativeDataSet(rows: 8, cols: 8, frames: 2, bitsAllocated: 8, bitsStored: 8)
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let nativeBytes = try nativeDS.writeChecked(using: writer)

        let recorder = InvocationRecorder()
        let customID = CodecProviderID(rawValue: "mock.successor")

        // Case A: Primary provider declares `canEncode == false` before execution.
        // With `.preselectPredecessorOnUnsupportedCapability`, `TransferSyntaxConverter` preselects `.j2kSwift`.
        let decliningCodec = MockJ2KCodec(
            providerID: customID,
            recorder: recorder,
            canDecodeDescriptor: { _ in false },
            canEncodeConfig: { _, _ in false },
            decodeAction: { _, _, _ in throw MockFailure(message: "Should not execute") },
            encodeAction: { _, _, _ in throw MockFailure(message: "Should not execute") }
        )
        let fallbackRegistry = CodecRegistry(
            j2kProvider: provider(decliningCodec),
            j2kFallbackPolicy: .preselectPredecessorOnUnsupportedCapability
        )
        let converterWithFallback = TransferSyntaxConverter(codecRegistry: fallbackRegistry)
        let fallbackResult = try converterWithFallback.transcode(
            dataSetData: nativeBytes,
            from: .explicitVRLittleEndian,
            to: .jpeg2000Lossless
        )
        XCTAssertEqual(fallbackResult.resolvedEncodeProviderID, .j2kSwift)
        XCTAssertTrue(recorder.snapshot.encodedCalls.isEmpty)

        // Case B: With `.strict` fallback policy, `canEncode == false` fails closed before execution.
        let strictRegistry = CodecRegistry(
            j2kProvider: provider(decliningCodec),
            j2kFallbackPolicy: .strict
        )
        let strictConverter = TransferSyntaxConverter(codecRegistry: strictRegistry)
        XCTAssertThrowsError(
            try strictConverter.transcode(
                dataSetData: nativeBytes,
                from: .explicitVRLittleEndian,
                to: .jpeg2000Lossless
            )
        )

        XCTAssertTrue(recorder.snapshot.encodedCalls.isEmpty)
    }

    // MARK: - 3. Canonical Multi-Fragment BOT, EOT/EOT-Lengths, and Stale EOT Removal

    func testMultiFragmentFramesAndStaleExtendedOffsetTableRemoval() throws {
        // Encode a 2-frame image to lossless J2K to get two valid J2K codestreams.
        let nativeDS = makeNativeDataSet(rows: 8, cols: 8, frames: 2, bitsAllocated: 8, bitsStored: 8)
        let descriptor = try XCTUnwrap(nativeDS.pixelDataDescriptor())
        let j2kCodec = J2KSwiftCodec()
        let codestreams = try j2kCodec.encode(
            try XCTUnwrap(nativeDS[.pixelData]?.valueData),
            descriptor: descriptor,
            configuration: .lossless
        )
        XCTAssertEqual(codestreams.count, 2)

        // Split Frame 0 across two fragments at an even boundary so serialization cannot insert padding inside its codestream
        // and keep Frame 1 in the third fragment: 3 fragments total for 2 frames.
        let splitPoint = max(2, (codestreams[0].count / 2) & ~1)
        let frag0 = Data(codestreams[0].prefix(splitPoint))
        let frag1 = Data(codestreams[0].dropFirst(splitPoint))
        let frag2 = codestreams[1]

        let frag0Span = UInt32(8 + frag0.count + (frag0.count % 2))
        let frag1Span = UInt32(8 + frag1.count + (frag1.count % 2))
        let botOffsets: [UInt32] = [0, frag0Span + frag1Span]

        var multiFragDS = nativeDS
        multiFragDS[.pixelData] = DataElement(
            tag: .pixelData,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [frag0, frag1, frag2],
            encapsulatedOffsetTable: botOffsets
        )

        // 3a. CompressionManager.decodePixelDataInPlace must resolve the 2 canonical frames via BOT
        // (previously it fell back to concatenating all 3 fragments into a single stream).
        var decodedInPlaceDS = multiFragDS
        let decodeProvider = try CompressionManager.decodePixelDataInPlace(
            dataSet: &decodedInPlaceDS,
            sourceSyntax: .jpeg2000Lossless,
            targetSyntax: .explicitVRLittleEndian
        )
        XCTAssertEqual(decodeProvider, .swiftJ2K)
        XCTAssertEqual(decodedInPlaceDS[.pixelData]?.valueData, nativeDS[.pixelData]?.valueData)

        // 3b. TransferSyntaxConverter lossless J2K -> HTJ2K on the 3-fragment / 2-frame dataset
        // must transcode the 2 canonical frames (not 3 fragments) and rebuild accurate BOT offsets.
        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let multiFragBytes = try multiFragDS.writeChecked(using: writer)
        let converter = TransferSyntaxConverter()
        let htj2kResult = try converter.transcode(
            dataSetData: multiFragBytes,
            from: .jpeg2000Lossless,
            to: .htj2kLossless
        )
        XCTAssertTrue(htj2kResult.wasTranscoded)
        XCTAssertEqual(htj2kResult.resolvedTranscodeProviderID, .swiftJ2K)
        XCTAssertNil(htj2kResult.resolvedDecodeProviderID)
        XCTAssertNil(htj2kResult.resolvedEncodeProviderID)
        XCTAssertThrowsError(try HTJ2KCodec.transcodeToHTJ2K(codestreams[0]))

        // Decode the transcoded HTJ2K dataset back to native and verify pixel equality.
        let roundTripResult = try converter.transcode(
            dataSetData: htj2kResult.data,
            from: .htj2kLossless,
            to: .explicitVRLittleEndian
        )
        let nativeResult = try parse(roundTripResult.data, syntax: .explicitVRLittleEndian)
        XCTAssertEqual(nativeResult[.pixelData]?.valueData, nativeDS[.pixelData]?.valueData)
        XCTAssertEqual(try nativeResult.tryPixelDataDescriptor(), descriptor)
        XCTAssertEqual(nativeResult.string(for: .sopInstanceUID), nativeDS.string(for: .sopInstanceUID))

        let parsedHT = try parse(htj2kResult.data, syntax: .htj2kLossless)
        let encoded = try XCTUnwrap(parsedHT.encapsulatedPixelData())
        XCTAssertEqual(encoded.fragments.count, 2)
        let firstHT = try XCTUnwrap(encoded.fragments.first)
        XCTAssertThrowsError(try HTJ2KCodec.transcodeFromHTJ2K(firstHT))
        XCTAssertEqual(encoded.offsetTable, [0, UInt32(8 + firstHT.count)])
        let htFile = DICOMFile.create(dataSet: parsedHT, transferSyntaxUID: TransferSyntax.htj2kLossless.uid)
        let samples = try XCTUnwrap(nativeDS[.pixelData]?.valueData)
        for frame in 0..<2 {
            let range = (frame * descriptor.bytesPerFrame)..<((frame + 1) * descriptor.bytesPerFrame)
            XCTAssertEqual(try htFile.pixelData(frame: frame).data, samples.subdata(in: range))
        }

        let reverse = try converter.transcode(dataSetData: htj2kResult.data, from: .htj2kLossless, to: .jpeg2000Lossless)
        XCTAssertEqual(reverse.resolvedTranscodeProviderID, .swiftJ2K)
        XCTAssertNil(reverse.resolvedDecodeProviderID)
        XCTAssertNil(reverse.resolvedEncodeProviderID)
        let reverseDataSet = try parse(reverse.data, syntax: .jpeg2000Lossless)
        let reverseFile = DICOMFile.create(dataSet: reverseDataSet, transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
        XCTAssertEqual(try reverseFile.tryPixelData().data, samples)
        XCTAssertEqual(try reverseDataSet.tryPixelDataDescriptor(), descriptor)

        // 3c. Valid EOT (7FE0,0001) + EOT-Lengths (7FE0,0002) with empty BOT:
        // verify canonical extraction succeeds and stale EOT tags are stripped upon transcode/decode.
        var eotDS = nativeDS
        let eotFrag0 = codestreams[0]
        let eotFrag1 = codestreams[1]
        let eotOffset1 = UInt64(8 + eotFrag0.count + (eotFrag0.count % 2))
        let eotBytes = makeUInt64LEData([0, eotOffset1])
        let eotLengthsBytes = makeUInt64LEData([UInt64(eotFrag0.count), UInt64(eotFrag1.count)])

        eotDS[.extendedOffsetTable] = DataElement(
            tag: .extendedOffsetTable,
            vr: .OV,
            length: UInt32(eotBytes.count),
            valueData: eotBytes
        )
        eotDS[.extendedOffsetTableLengths] = DataElement(
            tag: .extendedOffsetTableLengths,
            vr: .OV,
            length: UInt32(eotLengthsBytes.count),
            valueData: eotLengthsBytes
        )
        eotDS[.pixelData] = DataElement(
            tag: .pixelData,
            vr: .OB,
            length: 0xFFFFFFFF,
            valueData: Data(),
            encapsulatedFragments: [eotFrag0, eotFrag1],
            encapsulatedOffsetTable: []
        )

        let eotFile = DICOMFile.create(
            dataSet: eotDS,
            transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid
        )
        let kept = try MultiframePixelAssembler.extractFrame(from: eotFile, frame: 1, handling: .preserve)
        guard case .encapsulated(let keptCodestream) = kept.storage else {
            return XCTFail("Expected a preserved codestream")
        }
        XCTAssertEqual(keptCodestream, codestreams[1])
        let decodedFromEOTFile = try eotFile.tryPixelData()
        XCTAssertEqual(decodedFromEOTFile.data, nativeDS[.pixelData]?.valueData)

        let eotSerialized = try eotDS.writeChecked(using: writer)
        let eotToHTJ2K = try converter.transcode(
            dataSetData: eotSerialized,
            from: .jpeg2000Lossless,
            to: .htj2kLossless
        )
        // Stale (7FE0,0001) and (7FE0,0002) tags must be removed from the BOT-based output.
        let parsedEOTOutput = try parse(eotToHTJ2K.data, syntax: .htj2kLossless)
        XCTAssertNil(parsedEOTOutput[.extendedOffsetTable])
        XCTAssertNil(parsedEOTOutput[.extendedOffsetTableLengths])
        XCTAssertEqual(parsedEOTOutput[.pixelData]?.encapsulatedOffsetTable, encoded.offsetTable)
        XCTAssertEqual(try DICOMFile.create(dataSet: parsedEOTOutput, transferSyntaxUID: TransferSyntax.htj2kLossless.uid)
            .tryPixelData().data, samples)

        var eotDecodedInPlace = eotDS
        try CompressionManager.decodePixelDataInPlace(
            dataSet: &eotDecodedInPlace,
            sourceSyntax: .jpeg2000Lossless,
            targetSyntax: .explicitVRLittleEndian
        )
        XCTAssertNil(eotDecodedInPlace[.extendedOffsetTable])
        XCTAssertNil(eotDecodedInPlace[.extendedOffsetTableLengths])
    }

    func testMalformedAndConflictingOffsetTablesFailClosed() throws {
        let descriptor = PixelDataDescriptor(
            rows: 4,
            columns: 4,
            numberOfFrames: 2,
            bitsAllocated: 8,
            bitsStored: 8,
            highBit: 7,
            isSigned: false,
            samplesPerPixel: 1,
            photometricInterpretation: .monochrome2
        )
        let fragments = [Data([0x01, 0x02, 0x03, 0x04]), Data([0x05, 0x06, 0x07, 0x08])]

        // 1. Malformed EOT (7 bytes, not a multiple of 8) must NOT be treated as absent EOT
        // even though fragments.count == numberOfFrames (which would otherwise succeed via 1:1 fallback).
        let encapEmptyBOT = EncapsulatedPixelData(
            offsetTable: [],
            fragments: fragments,
            descriptor: descriptor
        )
        XCTAssertNil(
            encapEmptyBOT.makeFrameIndex(
                extendedOffsetTableData: Data([1, 2, 3, 4, 5, 6, 7]),
                extendedOffsetTableLengthsData: nil
            )
        )
        XCTAssertThrowsError(
            try encapEmptyBOT.resolveFrameIndex(
                extendedOffsetTableData: Data([1, 2, 3, 4, 5, 6, 7]),
                extendedOffsetTableLengthsData: nil
            )
        ) { error in
            XCTAssertEqual(error as? EncapsulatedFrameResolutionError, .malformedExtendedOffsetTable(byteCount: 7))
        }

        // 2. Conflicting BOT + EOT both populated must fail closed.
        let encapWithBOT = EncapsulatedPixelData(
            offsetTable: [0, 12],
            fragments: fragments,
            descriptor: descriptor
        )
        let validEOT = makeUInt64LEData([0, 12])
        XCTAssertThrowsError(
            try encapWithBOT.resolveFrameIndex(
                extendedOffsetTableData: validEOT,
                extendedOffsetTableLengthsData: nil
            )
        ) { error in
            XCTAssertEqual(error as? EncapsulatedFrameResolutionError, .conflictingOffsetTables)
        }

        // 3. Orphan EOT-Lengths (7FE0,0002) without EOT (7FE0,0001) must fail closed.
        let validEOTLengths = makeUInt64LEData([4, 4])
        XCTAssertThrowsError(
            try encapEmptyBOT.resolveFrameIndex(
                extendedOffsetTableData: nil,
                extendedOffsetTableLengthsData: validEOTLengths
            )
        ) { error in
            XCTAssertEqual(error as? EncapsulatedFrameResolutionError, .orphanExtendedOffsetTableLengths)
        }

        // 4. Conflicting EOT-Lengths value (declares 6 bytes when fragment 1 is 4 bytes) must fail closed.
        let wrongEOTLengths = makeUInt64LEData([4, 6])
        XCTAssertThrowsError(
            try encapEmptyBOT.resolveFrameIndex(
                extendedOffsetTableData: validEOT,
                extendedOffsetTableLengthsData: wrongEOTLengths
            )
        ) { error in
            XCTAssertEqual(
                error as? EncapsulatedFrameResolutionError,
                .conflictingExtendedOffsetTableLengths(frameIndex: 1, declaredLength: 6, actualByteLength: 4)
            )
        }
    }

    func testInvalidTablesRefuseBeforeDecodeInManagerConverterAndFrameAccess() throws {
        let recorder = InvocationRecorder()
        let registry = CodecRegistry(j2kProvider: provider(failingCodec(recorder, refusal: .malformed)))
        let fragments = [Data([1, 2]), Data([3, 4])]
        let cases: [(bot: [UInt32], eot: Data?, fragments: [Data])] = [
            ([], Data(repeating: 0, count: 7), fragments),      // partial EOT
            ([0, 10], makeUInt64LEData([0, 10]), fragments),    // both tables present
            ([0], nil, fragments),                             // incomplete BOT
            ([], nil, fragments + [Data([5, 6])])               // ambiguous frames
        ]
        for input in cases {
            var dataSet = makeNativeDataSet(rows: 4, cols: 4, frames: 2, bitsAllocated: 8, bitsStored: 8)
            dataSet[.pixelData] = DataElement(tag: .pixelData, vr: .OB, length: UInt32.max, valueData: Data(),
                                              encapsulatedFragments: input.fragments, encapsulatedOffsetTable: input.bot)
            if let eot = input.eot {
                dataSet[.extendedOffsetTable] = DataElement(tag: .extendedOffsetTable, vr: .OV,
                                                           length: UInt32(eot.count), valueData: eot)
            }
            let file = DICOMFile.create(dataSet: dataSet, transferSyntaxUID: TransferSyntax.jpeg2000Lossless.uid)
            XCTAssertThrowsError(try file.pixelData(frame: 1, codecRegistry: registry))
            XCTAssertThrowsError(try MultiframePixelAssembler.extractFrame(from: file, frame: 1, handling: .preserve))
            XCTAssertThrowsError(try TransferSyntaxConverter(codecRegistry: registry).transcode(
                dataSetData: dataSet.write(), from: .jpeg2000Lossless, to: .explicitVRLittleEndian
            ))
            XCTAssertThrowsError(try CompressionManager.decodePixelDataInPlace(
                dataSet: &dataSet, sourceSyntax: .jpeg2000Lossless, targetSyntax: .explicitVRLittleEndian,
                codecRegistry: registry
            ))
            XCTAssertTrue(recorder.snapshot.decodedFrames.isEmpty)
        }
    }

    // MARK: - 4. Checked Offset Builder Near 32-Bit / Int Boundaries

    func testCheckedOffsetBuilderNearBoundariesWithoutLargeAllocations() throws {
        // Odd fragment length (5 bytes -> padded 6 bytes + 8-byte item header = 14 bytes).
        let (offsets, totalBytes) = try EncapsulatedPixelData.buildCheckedBasicOffsetTable(
            forFragmentLengths: [5, 4],
            includeSingleFrameOffset: true
        )
        XCTAssertEqual(offsets, [0, 14])
        // 12 (7FE0,0010 header) + 8 (BOT header) + 8 (2 BOT entries) + 14 (frag 0) + 12 (frag 1) + 8 (delimiter) = 62
        XCTAssertEqual(totalBytes, 62)

        // Single fragment length equal to 0xFFFF_FFFF (undefined length sentinel) must fail closed.
        XCTAssertThrowsError(
            try EncapsulatedPixelData.buildCheckedBasicOffsetTable(
                forFragmentLengths: [Int(UInt32.max)],
                includeSingleFrameOffset: true
            )
        ) { error in
            XCTAssertEqual(
                error as? EncapsulatedOffsetBuildError,
                .fragmentLengthOutOfBounds(fragmentIndex: 0, length: Int(UInt32.max))
            )
        }

        // Two fragments whose individual lengths fit UInt32, but Frame 1's BOT offset exceeds UInt32.max:
        // Frag 0 length = 0xFFFF_FFF0 -> padded 0xFFFF_FFF0 + 8 = 0xFFFF_FFF8 (fits UInt32).
        // Frag 1 length = 16 -> Frame 1 starts at 0xFFFF_FFF8 (fits UInt32), Frame 2 starts at 0x1_0000_0010 (overflows UInt32).
        XCTAssertThrowsError(
            try EncapsulatedPixelData.buildCheckedBasicOffsetTable(
                forFragmentLengths: [0xFFFF_FFF0, 16, 16],
                includeSingleFrameOffset: true,
                maxSerializedBytes: Int.max
            )
        ) { error in
            XCTAssertEqual(
                error as? EncapsulatedOffsetBuildError,
                .basicOffsetTableOffsetOverflow(frameIndex: 2, offset: 0x1_0000_0010)
            )
        }

        // Total serialized length exceeding `maxSerializedBytes` cap refuses before allocation.
        XCTAssertThrowsError(
            try EncapsulatedPixelData.buildCheckedBasicOffsetTable(
                forFragmentLengths: [32, 32],
                includeSingleFrameOffset: true,
                maxSerializedBytes: 64
            )
        ) { error in
            guard case .totalSerializedLengthOutOfBounds(_, let maxAllowed) = error as? EncapsulatedOffsetBuildError else {
                XCTFail("Expected totalSerializedLengthOutOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(maxAllowed, 64)
        }
    }

    // MARK: - 5. Fidelity-Preserving Refusal of Implicit 16-to-8 Rescaling

    func testFidelityPreservingTranscodeRefusesImplicit16To8BitRescaling() throws {
        var ds16 = makeNativeDataSet(rows: 8, cols: 8, frames: 1, bitsAllocated: 16, bitsStored: 16, isSigned: true)
        ds16.setString("-1024", for: .rescaleIntercept, vr: .DS)
        ds16.setString("1", for: .rescaleSlope, vr: .DS)
        ds16.setString("40", for: .windowCenter, vr: .DS)
        ds16.setString("400", for: .windowWidth, vr: .DS)

        let writer = DICOMWriter(byteOrder: .littleEndian, explicitVR: true)
        let sourceBytes = try ds16.writeChecked(using: writer)

        // Keep lossy compression enabled in all three cases to reach precision negotiation.
        func convert(preserve: Bool, permitReduction: Bool) throws -> TranscodingResult {
            let config = TranscodingConfiguration(
                preferredSyntaxes: [.jpegBaseline], allowLossyCompression: true,
                preservePixelDataFidelity: preserve, allowBitDepthReductionTo8Bit: permitReduction
            )
            return try TransferSyntaxConverter(configuration: config).transcode(
                dataSetData: sourceBytes, from: .explicitVRLittleEndian, to: .jpegBaseline
            )
        }
        for (preserve, permit) in [(true, true), (false, false)] {
            XCTAssertThrowsError(try convert(preserve: preserve, permitReduction: permit)) { error in
                guard case .encodingFailed(let reason) = error as? TranscodingError else {
                    return XCTFail("Expected precision refusal, got \(error)")
                }
                XCTAssertTrue(reason.contains("bitsAllocated=16"), reason)
                XCTAssertTrue(reason.contains("isSigned=true"), reason)
            }
        }
        let reduced = try parse(convert(preserve: false, permitReduction: true).data, syntax: .jpegBaseline)
        XCTAssertEqual(reduced.uint16(for: .bitsAllocated), 8)
        XCTAssertEqual(reduced.uint16(for: .bitsStored), 8)
        XCTAssertEqual(reduced.uint16(for: .highBit), 7)
        XCTAssertEqual(reduced.uint16(for: .pixelRepresentation), 0)
        XCTAssertNil(reduced[.windowCenter])
        XCTAssertNil(reduced[.rescaleIntercept])
    }

    // MARK: - 6. Phase B: Part 2 CAP/CBD Header Inspection, Provider-Aware Part 2 Routing & Managed Init

    func testJ2KCodestreamInspectorParsesPart2CAPAndCBDAndPart15CAP() throws {
        // Construct minimal valid SOC + CAP (Pcap^2 = 0x4000_0000) + SIZ (3 comps, 8-bit) + CBD (signed 12-bit) + COD + SOT + SOD
        var stream = Data()
        func appendU16(_ v: UInt16) {
            stream.append(UInt8(v >> 8))
            stream.append(UInt8(v & 0xFF))
        }
        func appendU32(_ v: UInt32) {
            stream.append(UInt8((v >> 24) & 0xFF))
            stream.append(UInt8((v >> 16) & 0xFF))
            stream.append(UInt8((v >> 8) & 0xFF))
            stream.append(UInt8(v & 0xFF))
        }

        appendU16(0xFF4F) // SOC
        // CAP: Lcap=8, Pcap = Pcap^2 (0x4000_0000), Ccap^2 = 0x0001
        appendU16(0xFF50)
        appendU16(8)
        appendU32(0x4000_0000)
        appendU16(0x0001)
        // SIZ: Lsiz = 38 + 3*3 = 47, Rsiz = 0x8002, 16x16, Csiz = 3, Ssiz = 7 (unsigned 8-bit)
        appendU16(0xFF51)
        appendU16(47)
        appendU16(0x8002)
        appendU32(16); appendU32(16)
        appendU32(0); appendU32(0)
        appendU32(16); appendU32(16)
        appendU32(0); appendU32(0)
        appendU16(3)
        for _ in 0..<3 {
            stream.append(7) // unsigned 8-bit in SIZ
            stream.append(1)
            stream.append(1)
        }
        // CBD (0xFF78): uniform Ncbd = 0x8003, Bd = 0x8B (signed 12-bit), Lcbd = 5
        appendU16(0xFF78)
        appendU16(5)
        appendU16(0x8003)
        stream.append(0x8B)
        // COD (0xFF52): Lcod=12, Scod=0, SGcod(prog=0, layers=1, mct=4), SPcod(NL=1, xcb=4, ycb=4, style=0, wav=1)
        appendU16(0xFF52)
        appendU16(12)
        stream.append(0)
        stream.append(0)
        appendU16(1)
        stream.append(4)
        stream.append(1); stream.append(4); stream.append(4); stream.append(0); stream.append(1)
        // SOT + SOD + payload + EOC
        appendU16(0xFF90)
        appendU16(10)
        appendU16(0)
        appendU32(14)
        stream.append(0); stream.append(1)
        appendU16(0xFF93)
        appendU16(0xFFD9)

        let header = try XCTUnwrap(J2KCodestreamInspector.imageHeader(in: stream))
        XCTAssertTrue(header.hasCAPMarker)
        XCTAssertTrue(header.hasPart2CAPMarker)
        XCTAssertFalse(header.hasPart15CAPMarker)
        XCTAssertEqual(header.cbdComponents?.count, 3)
        XCTAssertEqual(header.logicalComponents.map(\.bitDepth), [12, 12, 12])
        XCTAssertEqual(header.logicalComponents.map(\.isSigned), [true, true, true])
    }

    func testAdmitInitializedRollsBackAndDebitsBudgetOnCallbackFailure() throws {
        let budget = try DICOMAllocationBudget()
        let ok = try DICOMByteBuffer.admitInitialized(count: 64, budget: budget, resource: .decoded) { slice in
            for i in 0..<slice.count { slice[i] = UInt8(i & 0xFF) }
            return nil
        }.get()
        XCTAssertEqual(ok.count, 64)
        XCTAssertEqual(budget.receipt.current.decoded, ok.capacity)
        XCTAssertEqual(ok.withUnsafeBytes { $0[7] }, 7)
        _ = consumeBuffer(ok)
        XCTAssertEqual(budget.receipt.current.decoded, 0)

        let failed = DICOMByteBuffer.admitInitialized(count: 128, budget: budget, resource: .decoded) { slice in
            slice[0] = 0xAA
            return DICOMManagedFailure(.codecFailure)
        }
        switch consume failed {
        case .success:
            XCTFail("Expected callback failure to roll back buffer")
        case .failure(let err):
            XCTAssertEqual(err.code, .codecFailure)
        }
        XCTAssertEqual(budget.receipt.current.decoded, 0, "Failed admitInitialized must release .decoded charge")
    }

    private func consumeBuffer(_ buffer: consuming DICOMByteBuffer) -> Int { buffer.count }

    func testDefaultRegistryPermitsPart2WhilePart1OnlyProviderRefusesInCompressionAndDiagnostics() throws {
        let native = makeNativeDataSet(rows: 8, cols: 8, frames: 1, bitsAllocated: 8, bitsStored: 8)
        let part10 = try DICOMFile.create(dataSet: native).write()
        let file = try DICOMFile.read(from: part10)
        let target92 = SelectableEncoding(transferSyntax: .jpeg2000Part2Lossless, intent: .notApplicable)

        // Default CodecRegistry.shared (SwiftJ2K 12.1.0) permits .92 in both checkConversion and CompressionManager
        XCTAssertNoThrow(
            try DICOMConverter.checkConversion(dicomFile: file, to: target92, codecRegistry: .shared)
        )
        let (_, sharedMetrics) = try CompressionManager(codecRegistry: .shared)
            .compressDataWithMetrics(part10, codec: "jpeg2000-part2-lossless-only", quality: nil)
        XCTAssertEqual(sharedMetrics.resolvedEncodeProviderID, .swiftJ2K)

        // A provider omitting .92 / .93 encode is refused by both checkConversion and CompressionManager
        let recorder = InvocationRecorder()
        let mockPart1Only = MockJ2KCodec(
            providerID: CodecProviderID(rawValue: "mock.part1only"),
            recorder: recorder,
            canDecodeDescriptor: { _ in true },
            canEncodeConfig: { _, _ in true },
            decodeAction: { _, d, _ in Data(repeating: 0, count: d.bytesPerFrame) },
            encodeAction: { _, _, _ in [Data([0xFF, 0x4F, 0xFF, 0xD9])] }
        )
        let part1OnlyProvider = J2KCodecProvider(
            providerID: CodecProviderID(rawValue: "mock.part1only"),
            supportedDecodingTransferSyntaxUIDs: [TransferSyntax.jpeg2000Lossless.uid],
            supportedEncodingTransferSyntaxUIDs: [TransferSyntax.jpeg2000Lossless.uid],
            makeDecoder: { _ in mockPart1Only },
            makeEncoder: { _ in mockPart1Only },
            canDecodeProfile: { _, _, _ in true },
            canEncodeProfile: { _, _, _ in true }
        )
        let part1OnlyRegistry = CodecRegistry(j2kProvider: part1OnlyProvider)
        XCTAssertThrowsError(
            try DICOMConverter.checkConversion(dicomFile: file, to: target92, codecRegistry: part1OnlyRegistry)
        )
        XCTAssertThrowsError(
            try CompressionManager(codecRegistry: part1OnlyRegistry)
                .compressData(part10, codec: "jpeg2000-part2-lossless-only", quality: nil)
        )
        XCTAssertTrue(recorder.snapshot.encodedCalls.isEmpty)
    }
}
