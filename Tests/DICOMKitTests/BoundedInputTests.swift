#if canImport(CryptoKit) && canImport(Darwin)
import Foundation
import CryptoKit
import Darwin
import Testing
@testable import DICOMKit
import DICOMCore

@Suite("Bounded verified strict input")
struct BoundedInputTests {
    private let rows = DICOMCore.Tag(group: 0x0028, element: 0x0010)
    private let pixel = DICOMCore.Tag(group: 0x7FE0, element: 0x0010)
    private let trailer = DICOMCore.Tag(group: 0x7FE1, element: 0x0010)
    private let sequence = DICOMCore.Tag(group: 0x0008, element: 0x1115)
    private let explicitUID = "1.2.840.10008.1.2.1"
    private let implicitUID = "1.2.840.10008.1.2"

    private func u16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }
    private func u32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func text(_ value: String) -> Data {
        var bytes = Data(value.utf8)
        if bytes.count % 2 != 0 { bytes.append(0) }
        return bytes
    }
    private func element(_ tag: DICOMCore.Tag, _ vr: String, _ value: Data, implicit: Bool = false,
                         length: UInt32? = nil, reserved: UInt16 = 0) -> Data {
        var bytes = u16(tag.group) + u16(tag.element)
        let count = length ?? UInt32(value.count)
        if implicit { return bytes + u32(count) + value }
        bytes += Data(vr.utf8)
        if ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "UC", "UR", "UT", "UN", "ZZ"].contains(vr) {
            bytes += u16(reserved) + u32(count)
        } else {
            bytes += u16(UInt16(count))
        }
        return bytes + value
    }
    private func marker(_ tag: DICOMCore.Tag, length: UInt32 = 0) -> Data {
        u16(tag.group) + u16(tag.element) + u32(length)
    }
    private func file(_ dataset: Data, syntax: String? = "1.2.840.10008.1.2.1",
                      extraMeta: Data = Data(), groupLengthDelta: Int = 0) -> Data {
        let transfer = syntax.map { element(.transferSyntaxUID, "UI", text($0)) } ?? Data()
        let body = transfer + extraMeta
        let length = element(DICOMCore.Tag(group: 2, element: 0), "UL", u32(UInt32(body.count + groupLengthDelta)))
        return Data(repeating: 0, count: 128) + Data("DICM".utf8) + length + body + dataset
    }
    private func image(implicit: Bool = false) -> Data {
        element(rows, "US", u16(2), implicit: implicit) + element(pixel, "OW", u16(42), implicit: implicit)
    }
    private func item(_ data: Data, undefined: Bool = false, declaredLength: UInt32? = nil) -> Data {
        marker(.item, length: declaredLength ?? (undefined ? 0xFFFFFFFF : UInt32(data.count)))
            + data + (undefined ? marker(.itemDelimitationItem) : Data())
    }
    private func sq(_ items: Data, undefined: Bool = false, declaredLength: UInt32? = nil, implicit: Bool = false) -> Data {
        element(sequence, "SQ", items, implicit: implicit, length: declaredLength ?? (undefined ? 0xFFFFFFFF : UInt32(items.count)))
            + (undefined ? marker(.sequenceDelimitationItem) : Data())
    }

    private func temporary(_ bytes: Data = Data()) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dcm")
        try bytes.write(to: url)
        return url
    }
    private func open(_ url: URL, budget: DICOMAllocationBudget,
                      options: ParsingOptions = .strict) throws -> BoundedDICOMFile {
        let source = try VerifiedFileByteSource(url: url, budget: budget)
        return try DICOMFile.readBounded(from: source, options: options)
    }
    private func bytes(_ buffer: DICOMByteBuffer) -> Data { buffer.withUnsafeBytes { Data($0) } }

    @Test("Canonical strict parser matches deferred metadata, nested items and trailing pixels", arguments: [false, true])
    func parity(implicit: Bool) throws {
        let nested = sq(item(image(implicit: implicit), undefined: true), undefined: true, implicit: implicit)
        let payload = file(nested + image(implicit: implicit) + element(trailer, "LO", text("AFTER"), implicit: implicit),
                           syntax: implicit ? implicitUID : explicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        var parsed: BoundedDICOMFile? = try open(url, budget: budget)
        #expect(parsed?.contentIdentity == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
        #expect(parsed?.dataSet.count == 4)
        #expect(try bytes(#require(parsed?.dataSet[pixel]).readValue()) == u16(42))
        #expect(try bytes(#require(parsed?.dataSet[trailer]).readValue()) == text("AFTER"))
        var items = 0
        try parsed?.dataSet[sequence]?.forEachItem { item throws in
            items += 1
            #expect(item.count == 2)
            let pixel = try #require(item[pixel])
            #expect(try bytes(pixel.readValue()) == u16(42))
        }
        #expect(items == 1)
        parsed = nil
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("Large and Unicode-padded transfer syntax values preserve existing strict admission",
          arguments: [" ", "\u{2000}", "\0"])
    func paddedSyntax(padding: String) throws {
        let uid = String(repeating: padding, count: 128) + explicitUID + String(repeating: padding, count: 128)
        let payload = file(image(), syntax: uid)
        let legacy = try DICOMFile.read(from: payload, options: .strict)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let parsed = try open(url, budget: DICOMAllocationBudget())
        #expect(parsed.transferSyntaxUID == legacy.fileMetaInformation.string(for: .transferSyntaxUID))
    }

    @Test("Leading UTF-8 BOM preserves legacy transfer-syntax decoding")
    func transferSyntaxBOM() throws {
        let payload = file(image(), syntax: "\u{FEFF} " + explicitUID + " ")
        let legacy = try DICOMFile.read(from: payload, options: .strict)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let parsed = try open(url, budget: DICOMAllocationBudget())
        #expect(parsed.transferSyntaxUID == legacy.fileMetaInformation.string(for: .transferSyntaxUID))
        for syntax in [" \u{FEFF}" + explicitUID, explicitUID + "\u{FEFF}"] {
            let malformed = file(image(), syntax: syntax)
            let url = try temporary(malformed); defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: (any Error).self) { try DICOMFile.read(from: malformed, options: .strict) }
            #expect(throws: (any Error).self) { try open(url, budget: DICOMAllocationBudget()) }
        }
    }

    @Test("Invalid BOT offsets preserve both parser and mapping rejection")
    func invalidBOT() throws {
        let options = ParsingOptions(strictEncapsulation: true,
            allowedTransferSyntaxUIDs: ["1.2.840.10008.1.2.4.50"], validationPolicy: .strict)
        for badOffset: UInt32 in [1, 9, 11, 20] {
            let bot = marker(.item, length: 8) + u32(0) + u32(badOffset)
            let chunks = marker(.item, length: 2) + Data([1, 2]) + marker(.item, length: 2) + Data([3, 4])
            let payload = file(element(pixel, "OB", bot + chunks + marker(.sequenceDelimitationItem), length: .max),
                syntax: "1.2.840.10008.1.2.4.50")
            let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
            #expect(throws: (any Error).self) { try DICOMFile.read(from: payload, options: options) }
            #expect(throws: (any Error).self) { try open(url, budget: DICOMAllocationBudget(), options: options) }
        }
    }

    @Test("Selected fragment assembly uses the canonical map without retaining other payloads")
    func fragments() throws {
        let bot = marker(.item, length: 8) + u32(0) + u32(20)
        let payloads = marker(.item, length: 2) + Data([1, 2]) + marker(.item, length: 2) + Data([3, 4])
            + marker(.item, length: 2) + Data([5, 6])
        let value = bot + payloads + marker(.sequenceDelimitationItem)
        let data = file(element(pixel, "OB", value, length: .max), syntax: "1.2.840.10008.1.2.4.50")
        let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let options = ParsingOptions(strictEncapsulation: true,
            allowedTransferSyntaxUIDs: ["1.2.840.10008.1.2.4.50"], validationPolicy: .strict)
        let parsed = try open(url, budget: budget, options: options)
        let element = try #require(parsed.dataSet[pixel])
        #expect(element.fragmentCount == 3)
        #expect(try bytes(element.readFrame(at: 0, numberOfFrames: 2)) == Data([1, 2, 3, 4]))
        #expect(try bytes(element.readFrame(at: 1, numberOfFrames: 2)) == Data([5, 6]))
        #expect(throws: DICOMError.self) { try element.readFrame(at: 0, numberOfFrames: 2, maximumBytes: 3) }
        #expect(throws: DICOMError.self) { try element.readFrame(at: 0, numberOfFrames: 3) }
    }

    @Test("Malformed strict structures reject on both storage strategies")
    func malformedParity() throws {
        let cases = [
            file(element(rows, "US", u16(2)) + element(rows, "US", u16(3))),
            file(sq(item(element(rows, "US", u16(2)) + element(rows, "US", u16(3))))),
            file(image() + Data([1, 2, 3])),
            file(element(pixel, "OW", u16(42), length: 4)),
            file(sq(item(image()), declaredLength: 4)),
            file(image(), groupLengthDelta: 2),
            file(image(), syntax: nil),
            file(element(rows, "US", Data([1]), length: 1))
        ]
        for data in cases {
            let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
            let budget = try DICOMAllocationBudget()
            #expect(throws: (any Error).self) { try DICOMFile.read(from: data, options: .strict) }
            #expect(throws: (any Error).self) { try open(url, budget: budget) }
            #expect(budget.receipt.currentTotal == 0)
        }
    }

    @Test("Source envelope around 128/256 MiB does not require a file-sized allocation",
          arguments: [134217726, 134217728, 134217730, 268435456])
    func largeSparseSource(size: Int) throws {
        var header = file(element(rows, "US", u16(2)))
        let payloadLength = size - header.count - 12
        header += element(pixel, "OW", Data(), length: UInt32(payloadLength))
        let url = try temporary(header); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size)); try handle.close()
        let budget = try DICOMAllocationBudget()
        var parsed: BoundedDICOMFile? = try open(url, budget: budget)
        #expect(parsed?.sourceByteCount == size)
        #expect(parsed?.dataSet[pixel]?.valueByteCount == payloadLength)
        #expect(try bytes(#require(parsed?.dataSet[pixel]).readValueRange((payloadLength - 2)..<payloadLength)) == Data([0, 0]))
        #expect(budget.receipt.peak.encoded <= 3 * 64 * 1024)
        #expect(budget.receipt.peakTotal < 1024 * 1024)
        parsed = nil
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("One byte beyond source cap fails before capture")
    func sourceOverLimit() throws {
        let url = try temporary(); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(VerifiedFileByteSource.maximumSourceBytes + 1)); try handle.close()
        let budget = try DICOMAllocationBudget()
        #expect(throws: VerifiedSourceError.sizeLimit) { try VerifiedFileByteSource(url: url, budget: budget) }
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("Replacement, truncation, append and same-size writes invalidate deferred reads", arguments: [0, 1, 2, 3])
    func sourceRaces(kind: Int) throws {
        let data = file(image())
        let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let parsed = try open(url, budget: budget)
        if kind == 0 { try data.write(to: url, options: .atomic) }
        else {
            let handle = try FileHandle(forWritingTo: url)
            if kind == 1 { try handle.truncate(atOffset: 100) }
            else if kind == 2 { try handle.seekToEnd(); try handle.write(contentsOf: Data([0])) }
            else { try handle.seek(toOffset: 0); try handle.write(contentsOf: Data([1])) }
            try handle.close()
        }
        #expect(throws: VerifiedSourceError.sourceChanged) { try parsed.dataSet[pixel]?.readValue() }
        #expect(throws: VerifiedSourceError.sourceChanged) { try parsed.validateSource() }
    }

    @Test("Symlinks are rejected and anchored descriptor ownership is independent")
    func anchor() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let link = url.appendingPathExtension("link"); defer { try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let budget = try DICOMAllocationBudget()
        #expect(throws: VerifiedSourceError.notRegularFile) { try VerifiedFileByteSource(url: link, budget: budget) }
        let fd = Darwin.open(url.path, O_RDONLY)
        #expect(fd >= 0)
        _ = Darwin.lseek(fd, 7, SEEK_SET)
        let source = try VerifiedFileByteSource(descriptor: fd, budget: budget)
        #expect(Darwin.lseek(fd, 0, SEEK_CUR) == 7)
        _ = Darwin.close(fd)
        #expect(try bytes(source.read(128..<132)) == Data("DICM".utf8))
    }

    @Test("Partial reads and EINTR preserve identity; altered bytes fail digest verification")
    func readFaults() throws {
        let data = file(image())
        let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
        let state = ReadFaultState()
        let hooks = VerifiedFileByteSource.Hooks(read: { fd, pointer, count, offset in
            if state.takeInterrupt() { errno = EINTR; return -1 }
            let result = Darwin.pread(fd, pointer, min(count, 7), offset)
            if state.corrupt, result > 0 { pointer?.assumingMemoryBound(to: UInt8.self).pointee ^= 1 }
            return result
        })
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(url: url, budget: budget,
            maximumBytes: VerifiedFileByteSource.maximumSourceBytes, hooks: hooks)
        #expect(try bytes(source.read(128..<132)) == Data("DICM".utf8))
        state.corrupt = true // metadata stays identical; only the digest can catch this.
        #expect(throws: VerifiedSourceError.sourceChanged) { try source.read(128..<132) }
    }

    @Test("Headers spanning source windows retain exact scalar parsing")
    func headerBoundary() throws {
        let base = file(Data())
        let padding = 65534 - base.count - 12
        let payload = base + element(trailer, "OB", Data(repeating: 0, count: padding)) + image()
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let parsed = try open(url, budget: budget)
        let value = try #require(parsed.dataSet[rows])
        #expect(try bytes(value.readValue()) == u16(2))
    }

    @Test("Deferred multi-block cancellation drops partial output and retains the valid source")
    func deferredCancellation() throws {
        let payload = Data(repeating: 0x5a, count: 3 * VerifiedFileByteSource.blockBytes)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let enabled = ReadFaultState()
        let hooks = VerifiedFileByteSource.Hooks(stage: { stage in
            if enabled.corrupt, case .verifiedBlock(1) = stage { throw CancellationError() }
        })
        let budget = try DICOMAllocationBudget()
        let source = try VerifiedFileByteSource(url: url, budget: budget,
            maximumBytes: VerifiedFileByteSource.maximumSourceBytes, hooks: hooks)
        let retained = budget.receipt.currentTotal
        enabled.corrupt = true
        #expect(throws: CancellationError.self) { try source.read(0..<payload.count) }
        #expect(budget.receipt.currentTotal == retained)
        enabled.corrupt = false
        #expect(try bytes(source.read(0..<2)) == Data([0x5a, 0x5a]))
    }

    @Test("A retained acquired value outlives source and index without duplicate charging")
    func valueOwnership() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        var retained: DICOMByteBuffer?
        do {
            let parsed = try open(url, budget: budget)
            let alias = parsed.dataSet
            let before = budget.receipt.currentTotal
            let otherAlias = parsed.dataSet
            #expect(budget.receipt.currentTotal == before)
            retained = try alias[pixel]?.readValue(resource: .decoded)
            withExtendedLifetime(otherAlias) {}
        }
        #expect(budget.receipt.currentTotal == AlignedPixelBuffer.pageSize + DICOMByteBuffer.controlCapacity)
        #expect(retained.map(bytes) == u16(42))
        try retained?.transfer(to: .resident)
        retained = nil
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("EOF probe retries observe cancellation without publishing a source")
    func eofCancellation() async throws {
        let payload = file(image())
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let signals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached {
            let hooks = VerifiedFileByteSource.Hooks(read: { fd, pointer, count, offset in
                if offset == payload.count {
                    signals.continuation.yield(())
                    errno = EINTR; return -1
                }
                return Darwin.pread(fd, pointer, count, offset)
            })
            return try VerifiedFileByteSource(url: url, budget: budget,
                maximumBytes: VerifiedFileByteSource.maximumSourceBytes, hooks: hooks)
        }
        var iterator = signals.stream.makeAsyncIterator()
        _ = await iterator.next()
        worker.cancel()
        do { _ = try await worker.value; Issue.record("Cancelled capture published a source") }
        catch is CancellationError {}
        signals.continuation.finish()
        #expect(budget.receipt.currentTotal == 0)
    }

    @Test("Cancellation during capture releases source/table/window ownership")
    func captureCancellation() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let hooks = VerifiedFileByteSource.Hooks(stage: { stage in
            if case .capturedBlock = stage { throw CancellationError() }
        })
        #expect(throws: CancellationError.self) {
            try VerifiedFileByteSource(url: url, budget: budget,
                maximumBytes: VerifiedFileByteSource.maximumSourceBytes, hooks: hooks)
        }
        #expect(budget.receipt.currentTotal == 0)
    }
}

private final class ReadFaultState: @unchecked Sendable {
    private let lock = NSLock()
    private var interrupted = false
    private var corrupted = false
    var corrupt: Bool {
        get { lock.lock(); defer { lock.unlock() }; return corrupted }
        set { lock.lock(); defer { lock.unlock() }; corrupted = newValue }
    }
    func takeInterrupt() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if interrupted { return false }
        interrupted = true; return true
    }
}
#endif
