#if canImport(CryptoKit) && canImport(Darwin)
import Foundation
import CryptoKit
import Darwin
import Testing
@testable import DICOMKit
@testable import DICOMCore

@Suite("Bounded verified strict input")
struct BoundedInputTests {
    private let rows = DICOMCore.Tag(group: 0x0028, element: 0x0010)
    private let pixel = DICOMCore.Tag(group: 0x7FE0, element: 0x0010)
    private let trailer = DICOMCore.Tag(group: 0x7FE1, element: 0x0010)
    private let sequence = DICOMCore.Tag(group: 0x0008, element: 0x1115)
    private let padding = DICOMCore.Tag(group: 0x0028, element: 0x0120)
    private let paddingLimit = DICOMCore.Tag(group: 0x0028, element: 0x0121)
    private let modalityLUT = DICOMCore.Tag(group: 0x0028, element: 0x3000)
    private let lutDescriptor = DICOMCore.Tag(group: 0x0028, element: 0x3002)
    private let lutData = DICOMCore.Tag(group: 0x0028, element: 0x3006)
    private let voiLUT = DICOMCore.Tag(group: 0x0028, element: 0x3010)
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
    private func open(_ url: URL, budget: borrowing DICOMAllocationBudget,
                      options: ParsingOptions = .strict) throws -> BoundedDICOMFile {
        let source = try VerifiedFileByteSource(url: url, budget: budget)
        return try DICOMFile.readBounded(from: source, options: options)
    }
    private func bytes(_ buffer: borrowing DICOMByteBuffer) -> Data { buffer.withUnsafeBytes { Data($0) } }
    private func value(_ file: borrowing BoundedDICOMFile, _ tag: DICOMCore.Tag) throws -> BoundedDICOMElement {
        let dataSet = try file.dataSet()
        guard let element = try dataSet.element(for: tag) else { throw TestFailure.missingElement }
        return element
    }
    private func expectFailure(_ body: () throws -> Void) {
        do { try body(); Issue.record("Expected failure") } catch {}
    }
    private func expectFailure(_ code: DICOMManagedFailure.Code, _ body: () throws -> Void) {
        do { try body(); Issue.record("Expected failure") }
        catch let failure as DICOMManagedFailure { #expect(failure.code == code) }
        catch let failure as DICOMParserFailure {
            if case .managed(let managed) = failure { #expect(managed.code == code) }
            else { Issue.record("Unexpected parser failure: \(failure)") }
        } catch { Issue.record("Unexpected failure: \(error)") }
    }
    private func testSource(_ url: URL, budget: borrowing DICOMAllocationBudget,
                            state: ReadFaultState) throws -> VerifiedFileByteSource {
        let context = Unmanaged.passUnretained(state).toOpaque()
        let hooks = VerifiedFileByteSource.Hooks(context: context, stage: { context, stage, block in
            guard let context else { return 0 }
            let state = Unmanaged<ReadFaultState>.fromOpaque(context).takeUnretainedValue()
            if state.cancelStage == stage && (state.cancelBlock < 0 || state.cancelBlock == block) {
                state.cancelled = true
            }
            return 0
        }, read: { context, fd, pointer, count, offset in
            guard let context else { return -1 }
            let state = Unmanaged<ReadFaultState>.fromOpaque(context).takeUnretainedValue()
            if state.cancelAtEOF == Int(offset) { state.cancelled = true; errno = EINTR; return -1 }
            if state.interrupt && state.takeInterrupt() { errno = EINTR; return -1 }
            let result = Darwin.pread(fd, pointer, min(count, state.maximumRead), offset)
            if state.corrupt, result > 0 { pointer?.assumingMemoryBound(to: UInt8.self).pointee ^= 1 }
            return result
        })
        let cancellation = state.cancellation
        var source: VerifiedFileByteSource?
        try url.path.withCString { path in
            source = try VerifiedFileByteSource(path: UnsafeBufferPointer(start: path, count: strlen(path) + 1),
                descriptor: nil, budget: budget, maximumBytes: VerifiedFileByteSource.maximumSourceBytes,
                cancellation: cancellation, hooks: hooks)
        }
        guard let result = consume source else { throw TestFailure.missingElement }
        return result
    }

    @Test("Canonical strict parser matches deferred metadata, nested items and trailing pixels", arguments: [false, true])
    func parity(implicit: Bool) throws {
        let nested = sq(item(image(implicit: implicit), undefined: true), undefined: true, implicit: implicit)
        let payload = file(nested + image(implicit: implicit) + element(trailer, "LO", text("AFTER"), implicit: implicit),
                           syntax: implicit ? implicitUID : explicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            #expect(parsed.contentIdentity.hexadecimal == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
            let dataSet = try parsed.dataSet()
            #expect(dataSet.count == 4)
            #expect(try bytes(value(parsed, pixel).readValue()) == u16(42))
            #expect(try bytes(value(parsed, trailer).readValue()) == text("AFTER"))
            var items = 0
            let sequenceValue = try value(parsed, sequence)
            try sequenceValue.forEachItem { item throws(DICOMParserFailure) in
                items += 1
                #expect(item.count == 2)
                guard let pixelValue = try item.element(for: pixel) else { Issue.record("Missing item pixel"); return }
                do throws(DICOMManagedFailure) { #expect(try bytes(pixelValue.readValue()) == u16(42)) }
                catch { throw .managed(error) }
            }
            #expect(items == 1)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Pixel padding VR follows signed Pixel Representation", arguments: [false, true])
    func signedPaddingVR(implicit: Bool) throws {
        let representation = DICOMCore.Tag(group: 0x0028, element: 0x0103)
        let padding = DICOMCore.Tag(group: 0x0028, element: 0x0120)
        let limit = DICOMCore.Tag(group: 0x0028, element: 0x0121)
        let payload = file(element(representation, "US", u16(1), implicit: implicit)
            + element(padding, "SS", u16(0xF800), implicit: implicit)
            + element(limit, "SS", u16(0xF801), implicit: implicit),
            syntax: implicit ? implicitUID : explicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let source = try VerifiedFileByteSource(url: url, budget: budget)
            let parsed = try DICOMFile.readBoundedOutcome(from: source, options: BoundedParsingOptions(.strict)).get()
            #expect(try value(parsed, padding).vr == .SS)
            #expect(try value(parsed, limit).vr == .SS)
            #expect(try bytes(value(parsed, padding).readValue()) == u16(0xF800))
            #expect(try bytes(value(parsed, limit).readValue()) == u16(0xF801))
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    private func paddingPair(implicit: Bool = true, vr: String = "US") -> Data {
        element(padding, vr, u16(0xF800), implicit: implicit)
            + element(paddingLimit, vr, u16(0xF801), implicit: implicit)
    }

    @Test("Implicit padding uses local or late parent context without sibling leakage",
          arguments: [false, true], [false, true])
    func paddingVRNestedContext(signed: Bool, undefined: Bool) throws {
        let rootVR: VR = signed ? .SS : .US
        let localVR: VR = signed ? .US : .SS
        let local = sq(item(paddingPair(), undefined: undefined), undefined: undefined, implicit: true)
            + element(.pixelRepresentation, "US", u16(signed ? 0 : 1), implicit: true) + paddingPair()
        let items = item(local, undefined: undefined) + item(paddingPair(), undefined: undefined)
        // SQ precedes Pixel Representation even in standard tag order.
        let payload = file(sq(items, undefined: undefined, implicit: true)
            + element(.pixelRepresentation, "US", u16(signed ? 1 : 0), implicit: true) + paddingPair(),
            syntax: implicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            #expect(try value(parsed, padding).vr == rootVR)
            #expect(try value(parsed, paddingLimit).vr == rootVR)
            let outer = try value(parsed, sequence)
            var actual: [VR] = []
            try outer.forEachItem { dataSet throws(DICOMParserFailure) in
                for tag in [padding, paddingLimit] {
                    if let element = try dataSet.element(for: tag) { actual.append(element.vr) }
                    else { Issue.record("Missing padding") }
                }
                if let inner = try dataSet.element(for: sequence) {
                    try inner.forEachItem { nested throws(DICOMParserFailure) in
                        for tag in [padding, paddingLimit] {
                            if let element = try nested.element(for: tag) { actual.append(element.vr) }
                            else { Issue.record("Missing nested padding") }
                        }
                    }
                }
            }
            #expect(actual == [localVR, localVR, localVR, localVR, rootVR, rootVR])
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Implicit padding refuses absent or malformed signedness", arguments: [0, 1, 2, 3, 4])
    func paddingVRRejectsContext(kind: Int) throws {
        let invalid = kind == 1 ? Data() : kind == 2 ? u16(2) : u16(0) + u16(1)
        let context = kind == 0 ? Data() : element(.pixelRepresentation, "US", invalid, implicit: true)
        let dataset: Data
        if kind == 4 {
            // A malformed local value cannot silently fall back to a valid parent.
            dataset = sq(item(context + paddingPair()), implicit: true)
                + element(.pixelRepresentation, "US", u16(1), implicit: true)
        } else { dataset = context + paddingPair() }
        let url = try temporary(file(dataset, syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do { _ = try open(url, budget: budget); Issue.record("Accepted unresolved padding VR") }
        catch let error as DICOMParserFailure {
            guard case .malformed(_, .pixelPaddingRepresentation) = error else {
                Issue.record("Unexpected error: \(error)"); return
            }
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("A local signedness override works without usable ancestor context", arguments: [false, true])
    func paddingVRLocalOverride(invalidParent: Bool) throws {
        let local = element(.pixelRepresentation, "US", u16(1), implicit: true) + paddingPair()
        let parent = invalidParent ? element(.pixelRepresentation, "US", u16(2), implicit: true) : Data()
        let url = try temporary(file(sq(item(local), implicit: true) + parent, syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let parsed = try open(url, budget: budget)
        let outer = try value(parsed, sequence)
        var count = 0
        try outer.forEachItem { dataSet throws(DICOMParserFailure) in
            for tag in [padding, paddingLimit] {
                if let element = try dataSet.element(for: tag) { #expect(element.vr == .SS); count += 1 }
            }
        }
        #expect(count == 2)
    }

    @Test("Explicit padding VR mismatches remain visible to strict consumers", arguments: [false, true])
    func paddingVRPreservesExplicitMismatch(signed: Bool) throws {
        let expected: VR = signed ? .SS : .US
        let encoded = signed ? "US" : "SS"
        let url = try temporary(file(element(.pixelRepresentation, "US", u16(signed ? 1 : 0))
            + paddingPair(implicit: false, vr: encoded)))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let parsed = try open(url, budget: budget)
        #expect(try value(parsed, padding).vr != expected)
        #expect(try value(parsed, paddingLimit).vr != expected)
        #expect(try bytes(value(parsed, padding).readValue()) == u16(0xF800))
    }

    @Test("Implicit padding requires exactly one 16-bit value", arguments: [0, 4])
    func paddingVRRejectsLength(count: Int) throws {
        for tag in [padding, paddingLimit] {
            let dataset = element(.pixelRepresentation, "US", u16(1), implicit: true)
                + element(tag, "US", Data(repeating: 0, count: count), implicit: true)
            let url = try temporary(file(dataset, syntax: implicitUID))
            defer { try? FileManager.default.removeItem(at: url) }
            let budget = try DICOMAllocationBudget()
            do { _ = try open(url, budget: budget); Issue.record("Accepted invalid padding length") }
            catch let error as DICOMParserFailure {
                guard case .malformed(_, .pixelPaddingLength) = error else {
                    Issue.record("Unexpected error: \(error)"); return
                }
            }
        }
    }

    @Test("Unrelated implicit datasets do not require valid Pixel Representation")
    func paddingVRAbsentIsUnchanged() throws {
        let url = try temporary(file(element(.pixelRepresentation, "US", u16(2), implicit: true), syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let parsed = try open(url, budget: budget)
        #expect(try bytes(value(parsed, .pixelRepresentation).readValue()) == u16(2))
    }

    @Test("Cancellation during padding resolution leaves unpublished storage balanced")
    func paddingVRFinalizationCancellation() throws {
        let url = try temporary(file(element(.pixelRepresentation, "US", u16(1), implicit: true)
            + paddingPair(), syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        do {
            let source = try VerifiedFileByteSource(url: url, budget: budget)
            let storage = try BoundedParseStorage.make(source: source).get()
            let capture = storage.capture
            var parser = DICOMParser(source: source.view, options: try BoundedParsingOptions(.strict), capture: capture)
            _ = try parser.parseFileMetaInformationCore(startOffset: 132).get()
            _ = try parser.parseDataSetCore(transferSyntax: .implicitLittleEndian).get()
            let before = budget.receipt
            var polls = 0
            withUnsafeMutablePointer(to: &polls) { pointer in
                let cancellation = DICOMCancellation(check: { context in
                    guard let context else { return true }
                    let count = context.assumingMemoryBound(to: Int.self)
                    count.pointee += 1
                    return count.pointee >= 4
                }, context: pointer)
                switch capture.withCancellation(cancellation).resolveImplicitContextualVR() {
                case .success: Issue.record("Expected cancellation during resolution")
                case .failure(let failure): #expect(failure == .managed(DICOMManagedFailure(.cancelled)))
                }
            }
            let firstPadding = capture.elements[capture.scopes[1].firstElement].nextSibling
            #expect(capture.elements[firstPadding].tag == padding)
            #expect(capture.elements[firstPadding].vr == .SS)
            let sealed = capture.state.pointee.sealed
            #expect(!sealed)
            #expect(budget.receipt == before)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    private func lutSequence(_ tag: DICOMCore.Tag, _ items: Data,
                             implicit: Bool = true, undefined: Bool = false) -> Data {
        element(tag, "SQ", items, implicit: implicit, length: undefined ? 0xFFFFFFFF : UInt32(items.count))
            + (undefined ? marker(.sequenceDelimitationItem) : Data())
    }

    private func lutPair(_ descriptor: Data, _ data: Data, implicit: Bool = true,
                         descriptorVR: String = "US", dataVR: String = "US") -> Data {
        element(lutDescriptor, descriptorVR, descriptor, implicit: implicit)
            + element(lutData, dataVR, data, implicit: implicit)
    }

    @discardableResult
    private func checkLUT(_ dataSet: borrowing BoundedDICOMDataSet, descriptor: Data,
                          vr: VR, data: Data, dataVR: VR = .OW) throws(DICOMParserFailure) -> Data {
        guard let descriptorElement = try dataSet.element(for: lutDescriptor),
              let dataElement = try dataSet.element(for: lutData) else {
            Issue.record("Missing LUT descriptor or data"); return Data()
        }
        #expect(descriptorElement.vr == vr)
        #expect(descriptorElement.length == UInt32(descriptor.count))
        #expect(descriptorElement.valueByteCount == descriptor.count)
        #expect(dataElement.vr == dataVR)
        #expect(dataElement.length == UInt32(data.count))
        #expect(dataElement.valueByteCount == data.count)
        do throws(DICOMManagedFailure) {
            let rawDescriptor = try bytes(descriptorElement.readValue())
            #expect(rawDescriptor == descriptor)
            #expect(try bytes(dataElement.readValue()) == data)
            return rawDescriptor
        } catch { throw .managed(error) }
    }

    @Test("Merged implicit reader retains native OW with signed padding and Modality LUT context",
          arguments: [UInt16(8), UInt16(16)])
    func mergedImplicitPixelAndContextualVR(allocated: UInt16) throws {
        let descriptor = u16(3) + u16(0xff80) + u16(8)
        let lutBytes = Data([1, 128, 255, 0])
        let pixelBytes = Data([0x80, 0x7f, 0xff, 0])
        let dataset = lutSequence(modalityLUT, item(lutPair(descriptor, lutBytes)))
            + element(padding, "US", u16(0xff80), implicit: true)
            + element(.bitsAllocated, "US", u16(allocated), implicit: true)
            + element(.pixelRepresentation, "US", u16(1), implicit: true)
            + element(pixel, "OB", pixelBytes, implicit: true)
        let payload = file(dataset, syntax: implicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            #expect(try value(parsed, pixel).vr == .OW)
            #expect(try bytes(value(parsed, pixel).readValue()) == pixelBytes)
            #expect(try value(parsed, padding).vr == .SS)
            #expect(try bytes(value(parsed, padding).readValue()) == u16(0xff80))
            let sequenceValue = try value(parsed, modalityLUT)
            #expect(sequenceValue.itemCount == 1)
            try sequenceValue.forEachItem { dataSet throws(DICOMParserFailure) in
                _ = try checkLUT(dataSet, descriptor: descriptor, vr: .SS, data: lutBytes)
            }
            let materialized = try DICOMFile.read(from: payload, options: .strict)
            #expect(materialized.dataSet[pixel]?.vr == .OW)
            #expect(materialized.dataSet[pixel]?.valueData == pixelBytes)
            #expect(materialized.dataSet[padding]?.vr == .SS)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Implicit Modality LUT values preserve packed bytes and unsigned descriptor fields",
          arguments: [false, true], [0, 1, 2])
    func modalityLUTImplicitValues(signed: Bool, kind: Int) throws {
        let countField: UInt16 = kind == 0 ? 3 : kind == 1 ? 0 : 0x8001
        let count = countField == 0 ? 65536 : Int(countField)
        let depth: UInt16 = kind == 0 ? 8 : 16
        let descriptor = u16(countField) + u16(0xF800) + u16(depth)
        var data = Data()
        if depth == 8 {
            data = Data([0x01, 0x80, 0xFF, 0x00]) // Three packed values, then the even-length pad.
        } else {
            for index in 0..<count { data += u16(UInt16(truncatingIfNeeded: index * 257)) }
        }
        let undefined = kind != 1
        // Pixel Representation deliberately follows the sequence and its items.
        let payload = file(lutSequence(modalityLUT, item(lutPair(descriptor, data), undefined: undefined),
                                      undefined: undefined)
            + element(.pixelRepresentation, "US", u16(signed ? 1 : 0), implicit: true), syntax: implicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            #expect(parsed.sourceByteCount == payload.count)
            #expect(parsed.contentIdentity.hexadecimal == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
            let sequenceValue = try value(parsed, modalityLUT)
            #expect(sequenceValue.itemCount == 1)
            var visited = 0
            try sequenceValue.forEachItem { dataSet throws(DICOMParserFailure) in
                visited += 1
                let raw = try checkLUT(dataSet, descriptor: descriptor, vr: signed ? .SS : .US, data: data)
                guard raw.count == 6 else { return }
                // Only the second field uses contextual signedness. Count zero means 65536.
                let first = UInt16(raw[0]) | UInt16(raw[1]) << 8
                let second = UInt16(raw[2]) | UInt16(raw[3]) << 8
                let third = UInt16(raw[4]) | UInt16(raw[5]) << 8
                #expect(first == countField)
                #expect((first == 0 ? 65536 : Int(first)) == count)
                #expect((signed ? Int(Int16(bitPattern: second)) : Int(second)) == (signed ? -2048 : 63488))
                #expect(third == depth)
            }
            #expect(visited == 1)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Modality LUT descriptors use nearest late context without sibling leakage",
          arguments: [false, true], [false, true])
    func modalityLUTNestedContext(signed: Bool, undefined: Bool) throws {
        let descriptor = u16(2) + u16(0xF800) + u16(16), data = u16(0xFFFF) + u16(0x8000)
        let pair = lutPair(descriptor, data)
        let localVR: VR = signed ? .US : .SS, rootVR: VR = signed ? .SS : .US
        let localRepresentation = element(.pixelRepresentation, "US", u16(signed ? 0 : 1), implicit: true)
        let nested = lutSequence(modalityLUT, item(pair, undefined: undefined), undefined: undefined)
        let generic = sq(item(nested + localRepresentation, undefined: undefined)
                         + item(nested, undefined: undefined), undefined: undefined, implicit: true)
        let direct = lutSequence(modalityLUT,
            item(pair + localRepresentation, undefined: undefined) + item(pair, undefined: undefined), undefined: undefined)
        let payload = file(generic + direct
            + element(.pixelRepresentation, "US", u16(signed ? 1 : 0), implicit: true), syntax: implicitUID)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            var outerIndex = 0, visited = 0
            let outer = try value(parsed, sequence)
            try outer.forEachItem { dataSet throws(DICOMParserFailure) in
                let expected = outerIndex == 0 ? localVR : rootVR
                outerIndex += 1
                guard let inner = try dataSet.element(for: modalityLUT) else { Issue.record("Missing nested LUT"); return }
                try inner.forEachItem { child throws(DICOMParserFailure) in
                    try checkLUT(child, descriptor: descriptor, vr: expected, data: data); visited += 1
                }
            }
            let directValue = try value(parsed, modalityLUT)
            var directIndex = 0
            try directValue.forEachItem { child throws(DICOMParserFailure) in
                try checkLUT(child, descriptor: descriptor, vr: directIndex == 0 ? localVR : rootVR, data: data)
                directIndex += 1; visited += 1
            }
            #expect(outerIndex == 2 && directIndex == 2 && visited == 4)
        }
        #expect(budget.receipt.currentTotal == baseline)
        // A valid local value is sufficient even when the parent has no usable context.
        for invalidParent in [false, true] {
            let parent = invalidParent ? element(.pixelRepresentation, "US", u16(2), implicit: true) : Data()
            let localURL = try temporary(file(lutSequence(modalityLUT,
                item(pair + localRepresentation, undefined: undefined), undefined: undefined) + parent, syntax: implicitUID))
            defer { try? FileManager.default.removeItem(at: localURL) }
            do {
                let parsed = try open(localURL, budget: budget)
                let outer = try value(parsed, modalityLUT)
                var visited = 0
                try outer.forEachItem { child throws(DICOMParserFailure) in
                    try checkLUT(child, descriptor: descriptor, vr: localVR, data: data); visited += 1
                }
                #expect(visited == 1)
            }
            #expect(budget.receipt.currentTotal == baseline)
        }
    }

    @Test("Modality LUT descriptors reject unresolved context and non-six-byte lengths",
          arguments: [0, 1, 2, 3, 4, 5, 6, 7, 8])
    func modalityLUTRejectsMalformed(kind: Int) throws {
        let valid = u16(1) + u16(0xF800) + u16(16)
        let descriptor = kind >= 5 ? Data(repeating: 0, count: [0, 2, 4, 8][kind - 5]) : valid
        let representation = kind == 1 ? Data() : kind == 2 ? u16(2) : kind == 3 || kind == 4 ? u16(0) + u16(1) : u16(1)
        let context = element(.pixelRepresentation, "US", representation, implicit: true)
        let local = kind == 4 ? context : Data()
        let parent = kind == 0 ? Data() : kind == 4 ? element(.pixelRepresentation, "US", u16(1), implicit: true) : context
        let url = try temporary(file(lutSequence(modalityLUT, item(lutPair(descriptor, u16(42)) + local))
            + parent, syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do { _ = try open(url, budget: budget); Issue.record("Accepted unresolved or malformed Modality LUT descriptor") }
        catch let failure as DICOMParserFailure {
            switch failure {
            case .malformed(_, .modalityLUTDescriptorRepresentation): #expect(kind < 5)
            case .malformed(_, .modalityLUTDescriptorLength): #expect(kind >= 5)
            default: Issue.record("Unexpected error: \(failure)")
            }
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Explicit Modality LUT descriptor and data VRs remain encoded", arguments: [false, true])
    func modalityLUTPreservesExplicit(signed: Bool) throws {
        let descriptor = u16(3) + u16(0xF800) + u16(8), data = Data([0x01, 0x80, 0xFF, 0])
        let encoded: VR = signed ? .US : .SS
        for dataVR in [VR.US, VR.OW] {
            let pair = lutPair(descriptor, data, implicit: false,
                               descriptorVR: signed ? "US" : "SS", dataVR: dataVR == .US ? "US" : "OW")
            let url = try temporary(file(lutSequence(modalityLUT, item(pair), implicit: false)
                + element(.pixelRepresentation, "US", u16(signed ? 1 : 0))))
            defer { try? FileManager.default.removeItem(at: url) }
            let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
            do {
                let parsed = try open(url, budget: budget)
                let outer = try value(parsed, modalityLUT)
                var visited = 0
                try outer.forEachItem { child throws(DICOMParserFailure) in
                    try checkLUT(child, descriptor: descriptor, vr: encoded, data: data, dataVR: dataVR); visited += 1
                }
                #expect(visited == 1)
            }
            #expect(budget.receipt.currentTotal == baseline)
        }
    }

    @Test("Implicit LUT Data uses OW outside Modality LUT while other descriptors stay unchanged",
          arguments: [0, 1, 2])
    func modalityLUTScopeExclusions(kind: Int) throws {
        // Deliberately four bytes: contextual descriptor length checks must not escape their scope.
        let descriptor = u16(0x8001) + u16(0xF800), data = Data([1, 0x80, 0xFF, 0])
        let pair = lutPair(descriptor, data)
        let generic = sq(item(pair), implicit: true)
        let voi = lutSequence(voiLUT, item(pair))
        let indirect = lutSequence(modalityLUT, item(generic + voi))
        let context = kind == 0 ? Data() : element(.pixelRepresentation, "US", u16(kind == 1 ? 1 : 2), implicit: true)
        let url = try temporary(file(pair + generic + voi + indirect + context, syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            let root = try parsed.dataSet()
            try checkLUT(root, descriptor: descriptor, vr: .US, data: data)
            var visited = 1
            for tag in [sequence, voiLUT] {
                let outer = try value(parsed, tag)
                try outer.forEachItem { child throws(DICOMParserFailure) in
                    try checkLUT(child, descriptor: descriptor, vr: .US, data: data); visited += 1
                }
            }
            let outer = try value(parsed, modalityLUT)
            try outer.forEachItem { child throws(DICOMParserFailure) in
                for tag in [sequence, voiLUT] {
                    guard let nested = try child.element(for: tag) else { Issue.record("Missing excluded nested sequence"); continue }
                    try nested.forEachItem { grandchild throws(DICOMParserFailure) in
                        try checkLUT(grandchild, descriptor: descriptor, vr: .US, data: data); visited += 1
                    }
                }
            }
            #expect(visited == 5)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Cancellation after Modality LUT descriptor resolution preserves unpublished storage")
    func modalityLUTFinalizationCancellation() throws {
        let descriptor = u16(3) + u16(0xF800) + u16(8), data = Data([1, 0x80, 0xFF, 0])
        let url = try temporary(file(element(.pixelRepresentation, "US", u16(1), implicit: true)
            + lutSequence(modalityLUT, item(lutPair(descriptor, data))), syntax: implicitUID))
        defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let source = try VerifiedFileByteSource(url: url, budget: budget)
            let storage = try BoundedParseStorage.make(source: source).get()
            let capture = storage.capture
            var parser = DICOMParser(source: source.view, options: try BoundedParsingOptions(.strict), capture: capture)
            _ = try parser.parseFileMetaInformationCore(startOffset: 132).get()
            _ = try parser.parseDataSetCore(transferSyntax: .implicitLittleEndian).get()
            let before = budget.receipt
            var polls = 0
            withUnsafeMutablePointer(to: &polls) { pointer in
                let cancellation = DICOMCancellation(check: { context in
                    guard let context else { return true }
                    let count = context.assumingMemoryBound(to: Int.self)
                    count.pointee += 1
                    return count.pointee >= 6
                }, context: pointer)
                switch capture.withCancellation(cancellation).resolveImplicitContextualVR() {
                case .success: Issue.record("Expected cancellation after descriptor resolution")
                case .failure(let failure): #expect(failure == .managed(DICOMManagedFailure(.cancelled)))
                }
            }
            let descriptorIndex = capture.scopes[2].firstElement
            let dataIndex = capture.elements[descriptorIndex].nextSibling
            #expect(capture.elements[descriptorIndex].tag == lutDescriptor)
            #expect(capture.elements[descriptorIndex].vr == .SS)
            let sealed = capture.state.pointee.sealed
            #expect(!sealed)
            #expect(budget.receipt == before)
            try capture.resolveImplicitContextualVR().get()
            #expect(capture.elements[dataIndex].tag == lutData)
            #expect(capture.elements[dataIndex].vr == .OW)
            #expect(budget.receipt == before)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    /// Deliberately nonthrowing: the complete qualified source/parser/value chain
    /// must propagate scalar outcomes without a compatibility `get()` call.
    private func acquirePixel(descriptor: Int32, budget: borrowing DICOMAllocationBudget,
                              options: BoundedParsingOptions, cancellation: DICOMCancellation)
        -> DICOMParserOutcome<UInt16> {
        var failure = DICOMParserFailure.unexpectedEndOfData
        guard let execution = parserAllocationOutcome(DICOMExecutionReservation.reserve(budget: budget))
            .takeValue(failure: &failure),
              let source = parserManagedOutcome(VerifiedFileByteSource.capture(descriptor: descriptor,
                budget: budget, execution: execution, cancellation: cancellation)).takeValue(failure: &failure),
              let parsed = DICOMFile.readBoundedOutcome(from: source, options: options, execution: execution,
                cancellation: cancellation).takeValue(failure: &failure),
              let dataSet = parsed.dataSetOutcome().takeValue(failure: &failure),
              let optionalPixel = dataSet.elementOutcome(for: pixel).takeValue(failure: &failure) else {
            return .failure(failure)
        }
        guard let pixelElement = consume optionalPixel else { return .failure(.unexpectedEndOfData) }
        switch pixelElement.readValueOutcome(cancellation: cancellation) {
        case .failure(let failure): return .failure(.managed(failure))
        case .success(let value):
            return value.withBorrowedBytes { bytes in
                guard bytes.count == 2 else { return .failure(.unexpectedEndOfData) }
                return .success(UInt16(bytes[0]) | UInt16(bytes[1]) << 8)
            }
        }
    }

    @Test("Nonthrowing source, parser and value outcomes preserve success and failure cleanup")
    func directOutcomePipeline() throws {
        let options = try BoundedParsingOptions(.strict)
        let budget = try DICOMAllocationBudget()
        let baseline = budget.receipt.currentTotal
        let good = file(image())
        var badPrefix = good
        badPrefix[128] = 0
        for (payload, cancelled, expected) in [
            (good, false, Optional<DICOMManagedFailure.Code>.none),
            (good, true, .cancelled),
            (badPrefix, false, .invalidPrefix),
            (Data([0]), false, .unexpectedEnd)
        ] {
            let url = try temporary(payload)
            defer { try? FileManager.default.removeItem(at: url) }
            let descriptor = Darwin.open(url.path, O_RDONLY)
            #expect(descriptor >= 0)
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            let cancellation = cancelled ? DICOMCancellation(check: { _ in true }) : .never
            switch acquirePixel(descriptor: descriptor, budget: budget, options: options,
                                cancellation: cancellation) {
            case .success(let pixel):
                #expect(expected == nil)
                #expect(pixel == 42)
            case .failure(.managed(let failure)):
                #expect(failure.code == expected)
            case .failure(let failure): Issue.record("Unexpected parser failure: \(failure)")
            }
            #expect(budget.receipt.currentTotal == baseline)
        }
    }

    @Test("Transfer Syntax UID preserves valid ASCII and trailing NUL accessor compatibility")
    func transferSyntaxTrailingNUL() throws {
        for implicit in [false, true] {
            let uid = implicit ? implicitUID : explicitUID
            // One padding NUL is normative when needed. Additional terminal NULs
            // exercise existing DataElement accessor compatibility, not a claim
            // that malformed VR padding is standard-conformant.
            for count in [0, 1, 128] {
                let payload = file(image(implicit: implicit), syntax: uid + String(repeating: "\0", count: count))
                let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
                let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
                do {
                    let parsed = try open(url, budget: budget)
                    let materialized = try DICOMFile.read(from: payload, options: .strict)
                    #expect(parsed.transferSyntaxUID == uid)
                    #expect(materialized.fileMetaInformation.string(for: .transferSyntaxUID) == uid)
                }
                #expect(budget.receipt.currentTotal == baseline)
            }
        }
    }

    @Test("Transfer Syntax UID rejects leading and Unicode whitespace in both strict readers")
    func paddedSyntax() throws {
        let candidates: [UInt32] = [0, 8, 9, 10, 11, 12, 13, 14, 31, 32, 33, 0x84, 0x85, 0x86,
            0x9f, 0xa0, 0xa1, 0x167f, 0x1680, 0x1681, 0x180e, 0x1fff, 0x2000, 0x2001,
            0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x200b,
            0x200c, 0x2027, 0x2028, 0x2029, 0x202a, 0x202e, 0x202f, 0x2030, 0x205e, 0x205f,
            0x2060, 0x2fff, 0x3000, 0x3001, 0xfeff]
        for scalarValue in candidates {
            guard let scalar = Unicode.Scalar(scalarValue) else { continue }
            let padding = String(repeating: String(scalar), count: 128)
            // Every leading candidate is illegal. Only trailing NUL is padding.
            let values = scalarValue == 0 ? [padding + explicitUID] : [padding + explicitUID, explicitUID + padding]
            for syntax in values {
                let payload = file(image(), syntax: syntax)
                let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
                let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
                expectFailure { _ = try DICOMFile.read(from: payload, options: .strict) }
                expectFailure { _ = try open(url, budget: budget) }
                #expect(budget.receipt.currentTotal == baseline)
            }
        }
    }

    @Test("Transfer Syntax UID rejects BOM, malformed UTF-8 and embedded padding")
    func transferSyntaxBOM() throws {
        let uid = Data(explicitUID.utf8)
        let malformedValues: [Data] = [
            Data([0xef, 0xbb, 0xbf]) + uid,
            uid + Data([0xef, 0xbb, 0xbf]),
            Data([0xff, 0xfe]) + uid,
            Data([0xc0, 0x80]) + uid,
            Data([0xed, 0xa0, 0x80]) + uid,
            Data("1.2\0.840.10008.1.2.1".utf8),
            Data("1.2 .840.10008.1.2.1".utf8)
        ]
        for malformed in malformedValues {
            var encoded = malformed
            if encoded.count % 2 != 0 { encoded.append(0) }
            let payload = file(image(), syntax: nil, extraMeta: element(.transferSyntaxUID, "UI", encoded))
            let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
            let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
            expectFailure { _ = try DICOMFile.read(from: payload, options: .strict) }
            expectFailure { _ = try open(url, budget: budget) }
            #expect(budget.receipt.currentTotal == baseline)
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
            let budget = try DICOMAllocationBudget()
            expectFailure { _ = try DICOMFile.read(from: payload, options: options) }
            expectFailure { _ = try open(url, budget: budget, options: options) }
        }
    }

    @Test("Selected fragment assembly uses the canonical map without retaining other payloads")
    func fragments() throws {
        let bot = marker(.item, length: 8) + u32(0) + u32(20)
        let payloads = marker(.item, length: 2) + Data([1, 2]) + marker(.item, length: 2) + Data([3, 4])
            + marker(.item, length: 2) + Data([5, 6])
        let data = file(element(pixel, "OB", bot + payloads + marker(.sequenceDelimitationItem), length: .max),
                        syntax: "1.2.840.10008.1.2.4.50")
        let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget()
        let options = ParsingOptions(strictEncapsulation: true,
            allowedTransferSyntaxUIDs: ["1.2.840.10008.1.2.4.50"], validationPolicy: .strict)
        let parsed = try open(url, budget: budget, options: options)
        let element = try value(parsed, pixel)
        #expect(element.fragmentCount == 3)
        #expect(try bytes(element.readFrame(at: 0, numberOfFrames: 2)) == Data([1, 2, 3, 4]))
        #expect(try bytes(element.readFrame(at: 1, numberOfFrames: 2)) == Data([5, 6]))
        expectFailure { _ = try element.readFrame(at: 0, numberOfFrames: 2, maximumBytes: 3) }
        expectFailure { _ = try element.readFrame(at: 0, numberOfFrames: 3) }
    }

    @Test("Malformed strict structures reject on both storage strategies")
    func malformedParity() throws {
        let cases = [file(element(rows, "US", u16(2)) + element(rows, "US", u16(3))),
            file(sq(item(element(rows, "US", u16(2)) + element(rows, "US", u16(3))))),
            file(image() + Data([1, 2, 3])), file(element(pixel, "OW", u16(42), length: 4)),
            file(sq(item(image()), declaredLength: 4)), file(image(), groupLengthDelta: 2),
            file(image(), syntax: nil), file(element(rows, "US", Data([1]), length: 1))]
        for data in cases {
            let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
            let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
            expectFailure { _ = try DICOMFile.read(from: data, options: .strict) }
            expectFailure { _ = try open(url, budget: budget) }
            #expect(budget.receipt.currentTotal == baseline)
        }
    }

    @Test("Source envelope around 128/256 MiB avoids file-sized storage",
          arguments: [134217726, 134217728, 134217730, 268435454, 268435456])
    func largeSparseSource(size: Int) throws {
        var header = file(element(rows, "US", u16(2)))
        let payloadLength = size - header.count - 12
        header += element(pixel, "OW", Data(), length: UInt32(payloadLength))
        let url = try temporary(header); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size)); try handle.close()
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        do {
            let parsed = try open(url, budget: budget)
            #expect(parsed.sourceByteCount == size)
            let pixel = try value(parsed, pixel)
            #expect(pixel.valueByteCount == payloadLength)
            #expect(try bytes(pixel.readValueRange((payloadLength - 2)..<payloadLength)) == Data([0, 0]))
            #expect(budget.receipt.peak.encoded <= 3 * 64 * 1024)
            #expect(budget.receipt.peakTotal < 1024 * 1024)
        }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("One byte beyond source cap fails before capture")
    func sourceOverLimit() throws {
        let url = try temporary(); defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(VerifiedFileByteSource.maximumSourceBytes + 1)); try handle.close()
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        expectFailure(.sizeLimit) { _ = try VerifiedFileByteSource(url: url, budget: budget) }
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Replacement, truncation, append and same-size writes invalidate every alias", arguments: [0, 1, 2, 3])
    func sourceRaces(kind: Int) throws {
        let data = file(image())
        let url = try temporary(data); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), parsed = try open(url, budget: budget)
        let alias = try parsed.share()
        if kind == 0 { try data.write(to: url, options: .atomic) }
        else {
            let handle = try FileHandle(forWritingTo: url)
            if kind == 1 { try handle.truncate(atOffset: 100) }
            else if kind == 2 { try handle.seekToEnd(); try handle.write(contentsOf: Data([0])) }
            else { try handle.seek(toOffset: 0); try handle.write(contentsOf: Data([1])) }
            try handle.close()
        }
        expectFailure(.sourceChanged) { _ = try value(parsed, pixel).readValue() }
        expectFailure(.sourceChanged) { try alias.validateSource() }
    }

    @Test("Symlinks reject and descriptor ownership remains independent")
    func anchor() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let link = url.appendingPathExtension("link"); defer { try? FileManager.default.removeItem(at: link) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        let budget = try DICOMAllocationBudget()
        expectFailure(.notRegularFile) { _ = try VerifiedFileByteSource(url: link, budget: budget) }
        let fd = Darwin.open(url.path, O_RDONLY)
        #expect(fd >= 0)
        _ = Darwin.lseek(fd, 7, SEEK_SET)
        let source = try VerifiedFileByteSource(descriptor: fd, budget: budget)
        #expect(Darwin.lseek(fd, 0, SEEK_CUR) == 7)
        _ = Darwin.close(fd)
        #expect(try bytes(source.read(128..<132)) == Data("DICM".utf8))
    }

    @Test("Partial reads and EINTR preserve identity; digest catches altered bytes")
    func readFaults() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let state = ReadFaultState(); state.interrupt = true; state.maximumRead = 7
        let budget = try DICOMAllocationBudget()
        let source = try testSource(url, budget: budget, state: state)
        #expect(try bytes(source.read(128..<132)) == Data("DICM".utf8))
        state.corrupt = true
        expectFailure(.sourceChanged) { _ = try source.read(128..<132) }
    }

    @Test("Headers spanning verification windows retain exact scalar parsing")
    func headerBoundary() throws {
        let base = file(Data()), padding = 65534 - base.count - 12
        let payload = base + element(trailer, "OB", Data(repeating: 0, count: padding)) + image()
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), parsed = try open(url, budget: budget)
        #expect(try bytes(value(parsed, rows).readValue()) == u16(2))
    }

    @Test("Deferred cancellation drops partial output but keeps source valid")
    func deferredCancellation() throws {
        let payload = Data(repeating: 0x5a, count: 3 * VerifiedFileByteSource.blockBytes)
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let state = ReadFaultState(), budget = try DICOMAllocationBudget()
        let source = try testSource(url, budget: budget, state: state)
        let retained = budget.receipt.currentTotal
        state.cancelStage = 2; state.cancelBlock = 1
        expectFailure(.cancelled) { _ = try source.read(0..<payload.count, cancellation: state.cancellation) }
        #expect(budget.receipt.currentTotal == retained)
        state.cancelled = false; state.cancelStage = -1
        #expect(try bytes(source.read(0..<2)) == Data([0x5a, 0x5a]))
    }

    @Test("Source does not retain an initializer cancellation context")
    func operationCancellationLifetime() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let state = ReadFaultState(), budget = try DICOMAllocationBudget()
        let source = try testSource(url, budget: budget, state: state)
        state.cancelled = true
        #expect(try bytes(source.read(128..<132)) == Data("DICM".utf8))
        expectFailure(.cancelled) {
            _ = try source.read(128..<132, cancellation: state.cancellation)
        }
        let options = try BoundedParsingOptions(.strict)
        expectFailure(.cancelled) {
            _ = try DICOMFile.readBounded(from: source, options: options, cancellation: state.cancellation)
        }
        let parsed = try DICOMFile.readBounded(from: source, options: options)
        #expect(parsed.sourceByteCount == source.count)
    }

    @Test("Every source/parser backing allocation failure rolls back to the ledger baseline", arguments: [false, true])
    func allocationFailureSweep(implicitPadding: Bool) throws {
        let descriptor = u16(3) + u16(0xF800) + u16(8), data = Data([1, 0x80, 0xFF, 0])
        let implicit = sq(item(paddingPair()), implicit: true)
            + lutSequence(modalityLUT, item(lutPair(descriptor, data)))
            + element(rows, "US", u16(2), implicit: true)
            + element(.pixelRepresentation, "US", u16(1), implicit: true) + paddingPair()
            + element(pixel, "OW", u16(42), implicit: true)
        let payload = implicitPadding ? file(implicit, syntax: implicitUID) : file(sq(item(image())) + image())
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        var reachedSuccess = false, failures = 0
        for failAfter in 0..<80 {
            let budget = try DICOMAllocationBudget(allocationFailureAfter: failAfter)
            let baseline = budget.receipt.currentTotal
            do {
                let parsed = try open(url, budget: budget)
                let frame = try value(parsed, pixel).readValueRange(0..<2)
                #expect(bytes(frame) == u16(42))
                if implicitPadding {
                    #expect(try value(parsed, padding).vr == .SS)
                    let outer = try value(parsed, modalityLUT)
                    var visited = 0
                    try outer.forEachItem { child throws(DICOMParserFailure) in
                        try checkLUT(child, descriptor: descriptor, vr: .SS, data: data); visited += 1
                    }
                    #expect(visited == 1)
                }
                reachedSuccess = true
            } catch let failure as DICOMManagedFailure {
                #expect(failure.allocation == .allocationFailed); failures += 1
            } catch let failure as DICOMParserFailure {
                if case .managed(let managed) = failure { #expect(managed.allocation == .allocationFailed) }
                else { Issue.record("Nonallocation failure in allocation sweep") }
                failures += 1
            }
            #expect(budget.receipt.currentTotal == baseline)
            if reachedSuccess { break }
        }
        #expect(reachedSuccess && failures > 10)
    }

    @Test("Value and view aliases retain exact backing through final destruction")
    func valueOwnership() throws {
        let url = try temporary(file(image())); defer { try? FileManager.default.removeItem(at: url) }
        let budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        var retained: DICOMByteBuffer?
        do {
            let parsed = try open(url, budget: budget)
            let alias = try parsed.dataSet(), before = budget.receipt.currentTotal
            let otherAlias = try parsed.dataSet()
            #expect(budget.receipt.currentTotal == before)
            guard let pixelValue = try alias.element(for: pixel) else { throw TestFailure.missingElement }
            retained = try pixelValue.readValue(resource: .decoded)
            #expect(otherAlias.count == alias.count)
        }
        #expect(budget.receipt.currentTotal == baseline + AlignedPixelBuffer.pageSize + DICOMByteBuffer.controlCapacity)
        if let retained { #expect(bytes(retained) == u16(42)); try retained.transfer(to: .resident) }
        else { Issue.record("Missing retained bytes") }
        retained = nil
        #expect(budget.receipt.currentTotal == baseline)
    }

    @Test("Capture and EOF-retry cancellation destroy all partial storage", arguments: [0, 1])
    func captureCancellation(kind: Int) throws {
        let payload = file(image())
        let url = try temporary(payload); defer { try? FileManager.default.removeItem(at: url) }
        let state = ReadFaultState(), budget = try DICOMAllocationBudget(), baseline = budget.receipt.currentTotal
        if kind == 0 { state.cancelStage = 0 } else { state.cancelAtEOF = payload.count }
        expectFailure(.cancelled) { _ = try testSource(url, budget: budget, state: state) }
        #expect(budget.receipt.currentTotal == baseline)
    }
}

private enum TestFailure: Error { case missingElement }
private final class ReadFaultState: @unchecked Sendable {
    var interrupt = false, corrupt = false, cancelled = false
    var maximumRead = Int.max, cancelStage = -1, cancelBlock = -1, cancelAtEOF = -1
    private var interrupted = false
    var cancellation: DICOMCancellation {
        DICOMCancellation(check: { context in
            guard let context else { return false }
            return Unmanaged<ReadFaultState>.fromOpaque(context).takeUnretainedValue().cancelled
        }, context: Unmanaged.passUnretained(self).toOpaque())
    }
    func takeInterrupt() -> Bool {
        if interrupted { return false }
        interrupted = true; return true
    }
}
#endif
