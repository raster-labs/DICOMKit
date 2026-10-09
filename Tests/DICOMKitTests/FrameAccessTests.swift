import XCTest
import Foundation
@testable import DICOMKit
import DICOMCore

/// M2 selected-frame access tests (RESEARCH_ADOPTION_PLAN.md M2): byte-identical
/// parity with the all-frames path, frame-index sources (BOT/EOT/1:1), fail-closed
/// malformed tables, native-path slicing, and mapped reads.
final class FrameAccessTests: XCTestCase {

    // MARK: - Builders

    private func el(_ tag: Tag, _ vr: VR, _ value: Data) -> DataElement {
        var v = value
        if v.count % 2 != 0 { v.append(vr == .UI ? 0x00 : 0x20) }
        return DataElement(tag: tag, vr: vr, length: UInt32(v.count), valueData: v, byteOrder: .littleEndian)
    }
    private func us(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }

    private func imageElements(rows: Int, cols: Int, frames: Int) -> [DataElement] {
        var elements: [DataElement] = [
            el(Tag(group: 0x0008, element: 0x0016), .UI, Data("1.2.840.10008.5.1.4.1.1.2".utf8)),
            el(Tag(group: 0x0028, element: 0x0002), .US, us(1)),
            el(Tag(group: 0x0028, element: 0x0004), .CS, Data("MONOCHROME2".utf8)),
        ]
        if frames > 1 {
            elements.append(el(Tag(group: 0x0028, element: 0x0008), .IS, Data("\(frames)".utf8)))
        }
        elements.append(contentsOf: [
            el(Tag(group: 0x0028, element: 0x0010), .US, us(UInt16(rows))),
            el(Tag(group: 0x0028, element: 0x0011), .US, us(UInt16(cols))),
            el(Tag(group: 0x0028, element: 0x0100), .US, us(16)),
            el(Tag(group: 0x0028, element: 0x0101), .US, us(16)),
            el(Tag(group: 0x0028, element: 0x0102), .US, us(15)),
            el(Tag(group: 0x0028, element: 0x0103), .US, us(0)),
        ])
        return elements
    }

    private func nativeFile(rows: Int = 8, cols: Int = 8, frames: Int = 5) throws -> DICOMFile {
        var elements = imageElements(rows: rows, cols: cols, frames: frames)
        var pixels = Data()
        for f in 0..<frames {
            for i in 0..<(rows * cols) {
                let v = UInt16(f * 1000 + i)
                pixels.append(UInt8(v & 0xFF)); pixels.append(UInt8(v >> 8))
            }
        }
        elements.append(el(Tag(group: 0x7FE0, element: 0x0010), .OW, pixels))
        let meta = DataSet(elements: [el(Tag(group: 0x0002, element: 0x0010), .UI,
                                         Data("1.2.840.10008.1.2.1".utf8))])
        let bytes = try DICOMFile(fileMetaInformation: meta,
                                  dataSet: DataSet(elements: elements)).write()
        return try DICOMFile.read(from: bytes)
    }

    /// RLE-compressed multiframe via the shared CompressionManager path.
    private func rleFile(rows: Int = 16, cols: Int = 16, frames: Int = 6) throws -> DICOMFile {
        let native = try nativeFile(rows: rows, cols: cols, frames: frames)
        let compressed = try CompressionManager().compressData(
            try native.write(), codec: "rle", quality: nil)
        return try DICOMFile.read(from: compressed)
    }

    // MARK: - Parity: pixelData(frame:) ≡ pixelData() slice

    func testNativeSelectedFrameMatchesAllFramesSlice() throws {
        let file = try nativeFile()
        let all = try XCTUnwrap(file.pixelData())
        for frame in 0..<5 {
            let selected = try file.pixelData(frame: frame)
            XCTAssertEqual(selected.data, all.frameData(at: frame),
                           "native frame \(frame) mismatch")
            XCTAssertEqual(selected.descriptor.numberOfFrames, 1)
        }
        XCTAssertEqual(file.pixelFrameCount, 5)
    }

    func testEncapsulatedSelectedFrameMatchesAllFramesSlice() throws {
        let file = try rleFile()
        let all = try XCTUnwrap(file.pixelData())
        for frame in 0..<6 {
            let selected = try file.pixelData(frame: frame)
            XCTAssertEqual(selected.data, all.frameData(at: frame),
                           "encapsulated frame \(frame) mismatch")
        }
    }

    func testInvalidFrameIndexThrows() throws {
        let file = try nativeFile()
        XCTAssertThrowsError(try file.pixelData(frame: 5))
        XCTAssertThrowsError(try file.pixelData(frame: -1))
    }

    // MARK: - Frame index sources

    func testFrameIndexOneFragmentPerFrame() throws {
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 3, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2)
        let encapsulated = EncapsulatedPixelData(
            offsetTable: [],
            fragments: [Data([1]), Data([2]), Data([3])],
            descriptor: descriptor)
        let index = try XCTUnwrap(encapsulated.makeFrameIndex())
        XCTAssertEqual(index.source, .oneFragmentPerFrame)
        XCTAssertEqual(encapsulated.frameData(at: 1, using: index), Data([2]))
    }

    func testFrameIndexBasicOffsetTableMultiFragmentFrames() throws {
        // Frame 0 = fragments 0+1 (4+2 bytes), frame 1 = fragment 2.
        // BOT offsets include 8-byte item headers: frame0@0, frame1@(8+4)+(8+2)=22.
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 2, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2)
        let encapsulated = EncapsulatedPixelData(
            offsetTable: [0, 22],
            fragments: [Data([1, 1, 1, 1]), Data([2, 2]), Data([3, 3, 3])],
            descriptor: descriptor)
        let index = try XCTUnwrap(encapsulated.makeFrameIndex())
        XCTAssertEqual(index.source, .basicOffsetTable)
        XCTAssertEqual(index.fragmentsPerFrame, [[0, 1], [2]])
        XCTAssertEqual(encapsulated.frameData(at: 0, using: index), Data([1, 1, 1, 1, 2, 2]))
        XCTAssertEqual(encapsulated.frameData(at: 1, using: index), Data([3, 3, 3]))
    }

    func testFrameIndexExtendedOffsetTableWinsAndIncludesHeaders() throws {
        // EOT offsets point at each frame's Item Tag, measured from the first Item
        // Tag after the Basic Offset Table (PS3.3 C.7.6.3.1.8), so they include the
        // 8-byte item headers: frame0@0, frame1@(8+4)+(8+2) = 22.
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 2, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2)
        let encapsulated = EncapsulatedPixelData(
            offsetTable: [],
            fragments: [Data([1, 1, 1, 1]), Data([2, 2]), Data([3, 3, 3])],
            descriptor: descriptor)
        let index = try XCTUnwrap(encapsulated.makeFrameIndex(extendedOffsets: [0, 22]))
        XCTAssertEqual(index.source, .extendedOffsetTable)
        XCTAssertEqual(index.fragmentsPerFrame, [[0, 1], [2]])
    }

    // MARK: - Fail closed

    func testMalformedOffsetTableFailsClosed() {
        let descriptor = PixelDataDescriptor(
            rows: 2, columns: 2, numberOfFrames: 2, bitsAllocated: 8, bitsStored: 8,
            highBit: 7, isSigned: false, samplesPerPixel: 1,
            photometricInterpretation: .monochrome2)
        // Offset 5 lands mid-fragment — must refuse, not slice the wrong bytes.
        let midFragment = EncapsulatedPixelData(
            offsetTable: [0, 5],
            fragments: [Data([1, 1, 1, 1]), Data([2, 2])],
            descriptor: descriptor)
        XCTAssertNil(midFragment.makeFrameIndex())

        // Non-monotonic offsets — refuse.
        let nonMonotonic = EncapsulatedPixelData(
            offsetTable: [0, 0],
            fragments: [Data([1, 1, 1, 1]), Data([2, 2])],
            descriptor: descriptor)
        XCTAssertNil(nonMonotonic.makeFrameIndex())

        // Multi-frame, no table, fragment count ≠ frame count — ambiguous, refuse.
        let ambiguous = EncapsulatedPixelData(
            offsetTable: [],
            fragments: [Data([1]), Data([2]), Data([3])],
            descriptor: descriptor)
        XCTAssertNil(ambiguous.makeFrameIndex())
    }

    // MARK: - M3: caller-owned / aligned decode

    func testAlignedSelectedFrameMatchesUnalignedNative() throws {
        let file = try nativeFile()
        for frame in [0, 2, 4] {
            let aligned = try file.alignedPixelData(frame: frame)
            XCTAssertEqual(aligned.data, try file.pixelData(frame: frame).data)
            XCTAssertEqual(aligned.alignedStorage?.isPageAligned, true,
                           "native frame \(frame) should land in page-aligned storage")
        }
    }

    func testAlignedSelectedFrameMatchesUnalignedRLE() throws {
        let file = try rleFile()
        for frame in [0, 3, 5] {
            let aligned = try file.alignedPixelData(frame: frame)
            XCTAssertEqual(aligned.data, try file.pixelData(frame: frame).data,
                           "RLE caller-owned decode must be byte-identical")
            XCTAssertEqual(aligned.alignedStorage?.isPageAligned, true)
        }
    }

    func testCallerOwnedRLEDecodeWritesDirectly() throws {
        let file = try rleFile()
        let encapsulated = try XCTUnwrap(file.dataSet.encapsulatedPixelData())
        let index = try XCTUnwrap(encapsulated.makeFrameIndex())
        let frameBytes = try XCTUnwrap(encapsulated.frameData(at: 1, using: index))
        let descriptor = encapsulated.descriptor
        let codec = RLECodec()

        let expected = try codec.decodeFrame(frameBytes, descriptor: descriptor, frameIndex: 1)
        var destination = [UInt8](repeating: 0xEE, count: descriptor.bytesPerFrame)
        let written = try destination.withUnsafeMutableBytes {
            try codec.decodeFrame(frameBytes, descriptor: descriptor, frameIndex: 1, into: $0)
        }
        XCTAssertEqual(written, descriptor.bytesPerFrame)
        XCTAssertEqual(Data(destination), expected)

        // Undersized destination must throw, never write out of bounds.
        var tiny = [UInt8](repeating: 0, count: 8)
        XCTAssertThrowsError(try tiny.withUnsafeMutableBytes {
            _ = try codec.decodeFrame(frameBytes, descriptor: descriptor, frameIndex: 1, into: $0)
        })
    }

    // MARK: - M4: bounded, cancellable parallel decode

    func testParallelDecodeMatchesSerial() async throws {
        let file = try rleFile()
        let serial = try XCTUnwrap(file.pixelData())
        let parallel = try await file.pixelDataParallel()
        XCTAssertEqual(parallel.data, serial.data)
        XCTAssertEqual(parallel.descriptor.numberOfFrames, serial.descriptor.numberOfFrames)

        let selected = try await file.pixelData(frames: [1, 4, 2])
        XCTAssertEqual(selected.count, 3)
        XCTAssertEqual(selected[4]?.data, serial.frameData(at: 4))
    }

    func testParallelDecodeRespectsByteBudgetWindow() throws {
        // Budget below one frame → window clamps to 1 (never zero, never storm).
        XCTAssertEqual(DICOMFile.maxConcurrentFrames(bytesPerFrame: 1_000_000,
                                                     maxInFlightBytes: 1), 1)
        // Huge budget → clamped by core count.
        XCTAssertLessThanOrEqual(
            DICOMFile.maxConcurrentFrames(bytesPerFrame: 1, maxInFlightBytes: .max),
            ProcessInfo.processInfo.activeProcessorCount)
        // Budget for two frames → window 2 (on any multi-core host).
        XCTAssertEqual(DICOMFile.maxConcurrentFrames(bytesPerFrame: 100,
                                                     maxInFlightBytes: 250), 2)
    }

    func testParallelDecodeTinyBudgetStillCompletes() async throws {
        let file = try rleFile()
        let serial = try XCTUnwrap(file.pixelData())
        // 1-byte budget: everything decodes serially through the window of 1.
        let result = try await file.pixelDataParallel(maxInFlightBytes: 1)
        XCTAssertEqual(result.data, serial.data)
    }

    func testParallelDecodeCancellation() async throws {
        let file = try rleFile(rows: 64, cols: 64, frames: 12)
        let task = Task {
            try await file.pixelData(frames: Array(0..<12), maxInFlightBytes: 1)
        }
        task.cancel()
        do {
            _ = try await task.value
            // Completing before the cancel lands is acceptable on a fast host.
        } catch is CancellationError {
            // Expected: cancellation propagated out of the decode loop.
        }
    }

    // MARK: - M5: progressive decode

    func testProgressiveDecodeJ2KCoarseThenExactFinal() async throws {
        let native = try nativeFile(rows: 64, cols: 64, frames: 2)
        let compressed = try CompressionManager().compressData(
            try native.write(), codec: "jpeg2000", quality: nil)
        let file = try DICOMFile.read(from: compressed)
        XCTAssertTrue(file.supportsProgressiveDecode)

        var updates: [ProgressiveFrameUpdate] = []
        for try await update in file.pixelDataProgressive(frame: 1) {
            updates.append(update)
        }

        XCTAssertGreaterThan(updates.count, 1, "JPEG 2000 should emit at least one coarse update")
        let final = try XCTUnwrap(updates.last)
        XCTAssertTrue(final.isFinal)
        // §12 gate: progressive final must equal direct full decode exactly.
        XCTAssertEqual(final.pixelData.data, try file.pixelData(frame: 1).data)
        XCTAssertEqual(final.pixelData.descriptor.rows, 64)

        // Any coarse update must be reduced and explicitly non-final.
        for coarse in updates.dropLast() {
            XCTAssertFalse(coarse.isFinal)
            XCTAssertLessThan(coarse.pixelData.descriptor.rows, 64)
            XCTAssertGreaterThan(coarse.resolutionLevel, 0)
        }
    }

    func testProgressiveDecodeFallsBackToSingleFinalForRLE() async throws {
        let file = try rleFile()
        XCTAssertFalse(file.supportsProgressiveDecode)
        var updates: [ProgressiveFrameUpdate] = []
        for try await update in file.pixelDataProgressive(frame: 2) {
            updates.append(update)
        }
        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates[0].isFinal)
        XCTAssertEqual(updates[0].pixelData.data, try file.pixelData(frame: 2).data)
    }

    // MARK: - Byte source / mapped read

    func testMappedAndPlainFileReadsAreIdentical() throws {
        let file = try nativeFile()
        let bytes = try file.write()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameAccessTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("t.dcm")
        try bytes.write(to: url)

        let plain = try DICOMFile.read(from: url)
        let mapped = try DICOMFile.read(from: url, options: .memoryMapped)
        XCTAssertEqual(plain.dataSet.count, mapped.dataSet.count)
        XCTAssertEqual(plain.pixelData()?.data, mapped.pixelData()?.data)
        XCTAssertEqual(try plain.pixelData(frame: 2).data,
                       try mapped.pixelData(frame: 2).data)
    }

    func testByteSourceBoundsChecked() throws {
        let source = InMemoryByteSource(data: Data([1, 2, 3, 4]))
        XCTAssertEqual(try source.bytes(in: 1..<3), Data([2, 3]))
        XCTAssertThrowsError(try source.bytes(in: 2..<5))
        XCTAssertEqual(source.count, 4)
    }
}
