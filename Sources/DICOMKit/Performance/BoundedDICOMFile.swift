// NEMA-verified: 2026a, checked 2026-10-14 — storage adapter; grammar remains in DICOMParser.
#if canImport(Darwin) || canImport(Glibc)
import Foundation
import DICOMCore

/// Strictly parsed structure with deferred verified values and explicit ownership.
public struct BoundedDICOMFile: ~Copyable, @unchecked Sendable {
    let storage: BoundedParseStorage
    /// Admitted syntax represented by a fixed scalar token.
    public let transferSyntax: BoundedTransferSyntax
    /// Static UID for caller compatibility.
    public var transferSyntaxUID: String { transferSyntax.uid }
    /// Fixed full-source digest.
    public var contentIdentity: DICOMContentDigest { storage.capture.source.identity }
    /// Complete captured source length.
    public var sourceByteCount: Int { storage.capture.source.count }
    /// Shared live and peak capacities.
    public var allocationReceipt: DICOMAllocationReceipt { storage.capture.source.receipt }
    init(storage: consuming BoundedParseStorage, transferSyntax: BoundedTransferSyntax) {
        self.storage = storage; self.transferSyntax = transferSyntax
    }
    /// Retain a deferred file-meta view without entering Swift's throwing runtime.
    public func fileMetaInformationOutcome() -> DICOMParserOutcome<BoundedDICOMDataSet> {
        switch storage.share() {
        case .success(let owner): return .success(BoundedDICOMDataSet(storage: owner, scope: 0))
        case .failure(let failure): return .failure(failure)
        }
    }
    /// Retain a deferred root view without another backing allocation.
    public func dataSetOutcome() -> DICOMParserOutcome<BoundedDICOMDataSet> {
        switch storage.share() {
        case .success(let owner): return .success(BoundedDICOMDataSet(storage: owner, scope: 1))
        case .failure(let failure): return .failure(failure)
        }
    }
    /// Explicitly share source and index ownership.
    public borrowing func shareOutcome() -> DICOMParserOutcome<Self> {
        switch storage.share() {
        case .success(let owner): return .success(Self(storage: owner, transferSyntax: transferSyntax))
        case .failure(let failure): return .failure(failure)
        }
    }
    /// Recheck source identity before publishing a result.
    public func validateSourceOutcome(cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<Void> {
        storage.capture.source.withCancellation(cancellation).validate()
    }
    /// Throwing compatibility adapter outside the qualified core.
    public func fileMetaInformation() throws(DICOMParserFailure) -> BoundedDICOMDataSet {
        try fileMetaInformationOutcome().get()
    }
    /// Throwing compatibility adapter outside the qualified core.
    public func dataSet() throws(DICOMParserFailure) -> BoundedDICOMDataSet { try dataSetOutcome().get() }
    /// Throwing compatibility adapter outside the qualified core.
    public borrowing func share() throws(DICOMParserFailure) -> Self { try shareOutcome().get() }
    /// Throwing compatibility adapter outside the qualified core.
    public func validateSource(cancellation: DICOMCancellation = .never) throws(DICOMManagedFailure) {
        try validateSourceOutcome(cancellation: cancellation).get()
    }
}

/// Owning view sharing the index's existing mapped control record.
public struct BoundedDICOMDataSet: ~Copyable, @unchecked Sendable {
    fileprivate let storage: BoundedParseStorage
    fileprivate let scope: Int
    private var index: BoundedParseCapture { storage.capture }
    init(storage: consuming BoundedParseStorage, scope: Int) { self.storage = storage; self.scope = scope }
    /// Immediate element count, excluding nested items.
    public var count: Int { index.scopes[scope].elementCount }
    /// Find one immediate element without constructing a dictionary.
    public func elementOutcome(for tag: Tag) -> DICOMParserOutcome<BoundedDICOMElement?> {
        var node = index.scopes[scope].firstElement
        while node >= 0 {
            let record = index.elements[node]
            if record.tag == tag {
                switch storage.share() {
                case .success(let owner):
                    return .success(BoundedDICOMElement(storage: owner, identifier: node))
                case .failure(let failure): return .failure(failure)
                }
            }
            node = record.nextSibling
        }
        return .success(nil)
    }
    /// Visit borrowed immediate elements synchronously without a container allocation.
    /// Caller callbacks must satisfy their separately qualified allocation contract.
    public func forEachOutcome(_ body: (borrowing BoundedDICOMElement) -> DICOMParserOutcome<Void>)
        -> DICOMParserOutcome<Void> {
        var node = index.scopes[scope].firstElement
        while node >= 0 {
            switch storage.share() {
            case .failure(let failure): return .failure(failure)
            case .success(let owner):
                let element = BoundedDICOMElement(storage: owner, identifier: node)
                if case .failure(let failure) = body(element) { return .failure(failure) }
            }
            node = index.elements[node].nextSibling
        }
        return .success(())
    }
    /// Throwing compatibility adapter outside the qualified core.
    public func element(for tag: Tag) throws(DICOMParserFailure) -> BoundedDICOMElement? {
        try elementOutcome(for: tag).get()
    }
    /// Throwing caller compatibility traversal, outside the qualified core.
    public func forEach(_ body: (borrowing BoundedDICOMElement) throws(DICOMParserFailure) -> Void)
        throws(DICOMParserFailure) {
        var node = index.scopes[scope].firstElement
        while node >= 0 {
            let element = BoundedDICOMElement(storage: try storage.share().get(), identifier: node)
            try body(element); node = index.elements[node].nextSibling
        }
    }
}

/// Owning deferred value or sequence view; source, admission and cancellation failures are scalar outcomes.
public struct BoundedDICOMElement: ~Copyable, @unchecked Sendable {
    fileprivate let storage: BoundedParseStorage
    fileprivate let identifier: Int
    private var index: BoundedParseCapture { storage.capture }
    private var record: BoundedParseCapture.Element { index.elements[identifier] }
    /// Element tag.
    public var tag: Tag { record.tag }
    /// Explicit or resolved implicit value representation. Implicit LUT Data uses
    /// OW; Modality LUT descriptors and pixel padding use contextual signedness.
    public var vr: VR { record.vr }
    /// Declared length, including the undefined-length sentinel.
    public var length: UInt32 { record.length }
    /// Value byte order.
    public var byteOrder: ByteOrder { record.byteOrder }
    /// Verified raw span length.
    public var valueByteCount: Int { record.range.count }
    /// Fragment count excluding the Basic Offset Table.
    public var fragmentCount: Int { record.fragmentCount }
    /// Whether an encapsulated envelope was captured.
    public var isEncapsulated: Bool { record.botRange != nil }
    /// Immediate sequence item count.
    public var itemCount: Int { record.itemCount }
    /// Explicitly retain the same source/index owner.
    public borrowing func shareOutcome() -> DICOMParserOutcome<Self> {
        switch storage.share() {
        case .success(let owner): return .success(Self(storage: owner, identifier: identifier))
        case .failure(let failure): return .failure(failure)
        }
    }
    /// Acquire the complete span in separately admitted storage.
    public func readValueOutcome(resource: DICOMAllocationClass = .metadata,
                                 cancellation: DICOMCancellation = .never) -> DICOMManagedOutcome<DICOMByteBuffer> {
        index.source.withCancellation(cancellation).read(record.range, resource: resource)
    }
    /// Visit borrowed immediate items without constructing an item array.
    public func forEachItemOutcome(_ body: (borrowing BoundedDICOMDataSet) -> DICOMParserOutcome<Void>)
        -> DICOMParserOutcome<Void> {
        var item = record.firstItem
        while item >= 0 {
            switch storage.share() {
            case .failure(let failure): return .failure(failure)
            case .success(let owner):
                let dataSet = BoundedDICOMDataSet(storage: owner, scope: item)
                if case .failure(let failure) = body(dataSet) { return .failure(failure) }
            }
            item = index.scopes[item].nextItem
        }
        return .success(())
    }
    /// Acquire one relative native frame range without materializing other frames.
    public func readValueRangeOutcome(_ relativeRange: Range<Int>, resource: DICOMAllocationClass = .encoded,
                                      cancellation: DICOMCancellation = .never)
        -> DICOMManagedOutcome<DICOMByteBuffer> {
        guard relativeRange.lowerBound >= 0, relativeRange.upperBound <= record.range.count else {
            return .failure(DICOMManagedFailure(.invalidRange))
        }
        let lower = record.range.lowerBound + relativeRange.lowerBound
        let upper = record.range.lowerBound + relativeRange.upperBound
        return index.source.withCancellation(cancellation).read(lower..<upper, resource: resource)
    }

    func transferSyntaxToken(cancellation: DICOMCancellation) -> DICOMParserOutcome<BoundedTransferSyntax> {
        let index = storage.capture.withCancellation(cancellation)
        var cursor = DICOMParserInput(source: index.source)
        let range = record.range
        var position = range.lowerBound, used = 0
        var trailingPadding = false, invalidToken = false
        var token: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0, 0, 0, 0, 0)
        return withUnsafeMutableBytes(of: &token) { output in
            while position < range.upperBound {
                if let failure = cancellation.failure { return .failure(.managed(failure)) }
                let byte: UInt8
                switch cursor.byte(at: position) {
                case .failure(let failure): return .failure(failure)
                case .success(let value): byte = value
                }
                position += 1
                // UI uses the default ASCII repertoire and trailing NUL padding
                // (PS3.5 2026a Table 6.2-1 / 9.1). Match DataElement.stringValue:
                // never trim leading bytes, whitespace, a UTF-8 BOM or text controls.
                // Repeated trailing NULs retain the materialized accessor's padding
                // compatibility; this lookup does not replace full VR validation.
                if byte == 0 { trailingPadding = true; continue }
                if trailingPadding || !((48...57).contains(byte) || byte == 46) || used >= output.count {
                    invalidToken = true
                } else {
                    output[used] = byte; used += 1
                }
            }
            guard used > 0 || invalidToken else { return .failure(.strict(.missingTransferSyntax)) }
            guard !invalidToken, let syntax = BoundedTransferSyntax.fromToken(
                UnsafeBufferPointer(start: output.baseAddress?.assumingMemoryBound(to: UInt8.self), count: used)) else {
                return .failure(.managed(DICOMManagedFailure(.invalidTransferSyntax)))
            }
            return .success(syntax)
        }
    }
    /// Acquire one frame using the canonical offset walker, validating all groups before allocation.
    public func readFrameOutcome(at frame: Int, numberOfFrames: Int, maximumBytes: Int = 64 * 1024 * 1024,
                                 cancellation: DICOMCancellation = .never) -> DICOMParserOutcome<DICOMByteBuffer> {
        let index = storage.capture.withCancellation(cancellation), record = self.record
        if let failure = cancellation.failure { return .failure(.managed(failure)) }
        guard let bot = record.botRange, frame >= 0, frame < numberOfFrames, maximumBytes >= 0 else {
            return .failure(.managed(DICOMManagedFailure(.invalidRange)))
        }
        var cursor = DICOMParserInput(source: index.source)
        var selected: Range<Int>?, traversalFailure: DICOMParserFailure?
        let valid = EncapsulatedPixelData.visitFrameGroups(numberOfFrames: numberOfFrames,
            fragmentCount: record.fragmentCount, fragmentLength: { position in
                if let failure = cancellation.failure { traversalFailure = .managed(failure); return nil }
                return index.fragments[record.firstFragment + position].range.count
            }, offsetCount: bot.count / 4, offsetAt: { position in
                if let failure = cancellation.failure { traversalFailure = .managed(failure); return nil }
                switch cursor.readUInt32LE(at: bot.lowerBound + position * 4) {
                case .failure(let failure): traversalFailure = failure; return nil
                case .success(let value):
                    guard let value else {
                        traversalFailure = .managed(DICOMManagedFailure(.unexpectedEnd)); return nil
                    }
                    return UInt64(value)
                }
            }, extended: false) { position, range, _ in
                if let failure = cancellation.failure { traversalFailure = .managed(failure); return false }
                if position == frame { selected = range }; return true
            }
        if let failure = traversalFailure { return .failure(failure) }
        guard valid, let selected else { return .failure(.managed(DICOMManagedFailure(.malformed))) }
        var total = 0
        for fragment in selected {
            if let failure = cancellation.failure { return .failure(.managed(failure)) }
            let length = index.fragments[record.firstFragment + fragment].range.count
            guard total <= maximumBytes, length <= maximumBytes - total else {
                return .failure(.managed(DICOMManagedFailure(.limitExceeded, maximumBytes)))
            }
            total += length
        }
        if case .failure(let failure) = index.source.validate() { return .failure(.managed(failure)) }
        var failure = DICOMManagedFailure(.invalidOptions)
        guard let output = index.source.withBorrowedBudget({ budget in
            DICOMByteBuffer.admit(count: total, budget: budget, resource: .encoded)
        }).takeValue(failure: &failure) else { return .failure(.managed(failure)) }
        let bytes = output.unsafeMutableBytes
        var offset = 0
        for fragment in selected {
            let range = index.fragments[record.firstFragment + fragment].range
            if case .failure(let failure) = index.source.copy(range,
                to: UnsafeMutableRawBufferPointer(rebasing: bytes[offset..<offset + range.count])) {
                return .failure(.managed(failure))
            }
            offset += range.count
        }
        if case .failure(let failure) = index.source.validate() { return .failure(.managed(failure)) }
        return .success(output)
    }

    /// Throwing compatibility adapter outside the qualified core.
    public borrowing func share() throws(DICOMParserFailure) -> Self { try shareOutcome().get() }
    /// Throwing compatibility adapter outside the qualified core.
    public func readValue(resource: DICOMAllocationClass = .metadata, cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> DICOMByteBuffer {
        try readValueOutcome(resource: resource, cancellation: cancellation).get()
    }
    /// Throwing compatibility traversal outside the qualified core.
    public func forEachItem(_ body: (borrowing BoundedDICOMDataSet) throws(DICOMParserFailure) -> Void)
        throws(DICOMParserFailure) {
        var item = record.firstItem
        while item >= 0 {
            let dataSet = BoundedDICOMDataSet(storage: try storage.share().get(), scope: item)
            try body(dataSet); item = index.scopes[item].nextItem
        }
    }
    /// Throwing compatibility adapter outside the qualified core.
    public func readValueRange(_ relativeRange: Range<Int>, resource: DICOMAllocationClass = .encoded,
                               cancellation: DICOMCancellation = .never)
        throws(DICOMManagedFailure) -> DICOMByteBuffer {
        try readValueRangeOutcome(relativeRange, resource: resource, cancellation: cancellation).get()
    }
    /// Throwing compatibility adapter outside the qualified core.
    public func readFrame(at frame: Int, numberOfFrames: Int, maximumBytes: Int = 64 * 1024 * 1024,
                          cancellation: DICOMCancellation = .never) throws(DICOMParserFailure) -> DICOMByteBuffer {
        try readFrameOutcome(at: frame, numberOfFrames: numberOfFrames, maximumBytes: maximumBytes,
                             cancellation: cancellation).get()
    }
}

@inline(__always)
func parserManagedOutcome<Value: ~Copyable>(_ outcome: consuming DICOMManagedOutcome<Value>)
    -> DICOMParserOutcome<Value> {
    switch consume outcome {
    case .success(let value): return .success(value)
    case .failure(let failure): return .failure(.managed(failure))
    }
}
@inline(__always)
func parserAllocationOutcome<Value: ~Copyable>(_ outcome: consuming DICOMAllocationOutcome<Value>)
    -> DICOMParserOutcome<Value> {
    switch consume outcome {
    case .success(let value): return .success(value)
    case .failure(let failure): return .failure(.managed(DICOMManagedFailure(allocation: failure)))
    }
}

struct BoundedParseState: ~Copyable {
    let source: VerifiedFileByteSource
    let budget: DICOMAllocationBudget
    var scopes: DICOMStorageVector<BoundedParseCapture.Scope>
    var elements: DICOMStorageVector<BoundedParseCapture.Element>
    var fragments: DICOMStorageVector<BoundedParseCapture.Fragment>
    var membership: DICOMStorageVector<BoundedParseCapture.Membership>
    var membershipCount = 0, currentScope = 0, currentSequence = -1
    var hasContextualVR = false
    var sealed = false
    static func make(source: borrowing VerifiedFileByteSource, budget: borrowing DICOMAllocationBudget)
        -> DICOMParserOutcome<Self> {
        var failure = DICOMParserFailure.unexpectedEndOfData
        guard let retainedSource = parserManagedOutcome(source.shareOutcome()).takeValue(failure: &failure),
              let retainedBudget = parserAllocationOutcome(budget.shareOutcome()).takeValue(failure: &failure),
              var scopes = parserAllocationOutcome(DICOMStorageVector<BoundedParseCapture.Scope>.make(budget: budget))
                .takeValue(failure: &failure),
              let elements = parserAllocationOutcome(
                DICOMStorageVector<BoundedParseCapture.Element>.make(budget: budget))
                .takeValue(failure: &failure),
              let fragments = parserAllocationOutcome(
                DICOMStorageVector<BoundedParseCapture.Fragment>.make(budget: budget))
                .takeValue(failure: &failure),
              let membership = parserAllocationOutcome(
                DICOMStorageVector<BoundedParseCapture.Membership>.make(budget: budget))
                .takeValue(failure: &failure) else { return .failure(failure) }
        for _ in 0..<2 {
            if case .failure(let failure) = scopes.appendOutcome(.init()) {
                return .failure(.managed(DICOMManagedFailure(allocation: failure)))
            }
        }
        return .success(Self(source: retainedSource, budget: retainedBudget, scopes: scopes,
                             elements: elements, fragments: fragments, membership: membership))
    }
}

struct BoundedParseStorage: ~Copyable {
    let owner: DICOMByteBuffer
    var capture: BoundedParseCapture {
        guard let base = owner.unsafeMutableBytes.baseAddress else { preconditionFailure("Missing index backing") }
        return BoundedParseCapture(state: base.assumingMemoryBound(to: BoundedParseState.self))
    }
    static func make(source: borrowing VerifiedFileByteSource) -> DICOMParserOutcome<Self> {
        var failure = DICOMParserFailure.unexpectedEndOfData
        guard let owner = parserManagedOutcome(source.view.withBorrowedBudget { budget in
            DICOMByteBuffer.admit(count: MemoryLayout<BoundedParseState>.stride, budget: budget, resource: .metadata)
        }).takeValue(failure: &failure),
              let state = source.view.withBorrowedBudget({ budget in
                  BoundedParseState.make(source: source, budget: budget)
              }).takeValue(failure: &failure) else { return .failure(failure) }
        guard let base = owner.unsafeMutableBytes.baseAddress else {
            return .failure(.managed(DICOMManagedFailure(.invalidOptions)))
        }
        let pointer = base.bindMemory(to: BoundedParseState.self, capacity: 1)
        pointer.initialize(to: state)
        if case .failure(let failure) = owner.installFinalizerOutcome({ pointer, _ in
            pointer?.assumingMemoryBound(to: BoundedParseState.self).deinitialize(count: 1)
        }) {
            pointer.deinitialize(count: 1)
            return .failure(.managed(DICOMManagedFailure(allocation: failure)))
        }
        return .success(Self(owner: owner))
    }
    borrowing func share() -> DICOMParserOutcome<Self> {
        switch owner.shareOutcome() {
        case .success(let owner): return .success(Self(owner: owner))
        case .failure(let failure): return .failure(.managed(DICOMManagedFailure(allocation: failure)))
        }
    }
}

/// Internal borrowed builder view pinned by the owning source/index.
struct BoundedParseCapture {
    enum PixelRepresentation { case absent, unsigned, signed, invalid }
    struct Scope {
        var firstElement = -1, lastElement = -1, elementCount = 0, nextItem = -1
        var parent = -1, sequenceElement = -1
        var pixelRepresentation: PixelRepresentation = .absent
    }
    struct Element {
        let tag: Tag, length: UInt32, byteOrder: ByteOrder
        var vr: VR
        var range: Range<Int>
        var nextSibling = -1, firstItem = -1, lastItem = -1, itemCount = 0
        var firstFragment = -1, fragmentCount = 0
        var botRange: Range<Int>?
    }
    struct Fragment { let range: Range<Int>; let streamOffset: Int }
    struct Membership { var scope = -1; var tag: UInt32 = 0 }
    let state: UnsafeMutablePointer<BoundedParseState>
    var cancellation: DICOMCancellation = .never
    func withCancellation(_ cancellation: DICOMCancellation) -> Self { Self(state: state, cancellation: cancellation) }
    var source: VerifiedSourceView { state.pointee.source.view.withCancellation(cancellation) }
    var scopes: DICOMStorageVector<Scope> { _read { yield state.pointee.scopes } }
    var elements: DICOMStorageVector<Element> { _read { yield state.pointee.elements } }
    var fragments: DICOMStorageVector<Fragment> { _read { yield state.pointee.fragments } }
    var currentScope: Int {
        get { state.pointee.currentScope }
        nonmutating set { state.pointee.currentScope = newValue }
    }
    var currentSequence: Int {
        get { state.pointee.currentSequence }
        nonmutating set { state.pointee.currentSequence = newValue }
    }
    func seal() -> DICOMParserOutcome<Void> {
        if case .failure(let failure) = source.validate() { return .failure(.managed(failure)) }
        state.pointee.membership.releaseStorage(); state.pointee.sealed = true
        return .success(())
    }
    func setPixelRepresentation(_ value: UInt16?) {
        precondition(!state.pointee.sealed)
        let representation: PixelRepresentation
        switch value {
        case 0: representation = .unsigned
        case 1: representation = .signed
        default: representation = .invalid
        }
        state.pointee.scopes[currentScope].pixelRepresentation = representation
    }
    private static func isPixelPadding(_ tag: Tag) -> Bool {
        tag.group == 0x0028 && (tag.element == 0x0120 || tag.element == 0x0121)
    }
    /// Resolve the supported implicit contextual VRs before publication.
    /// The nearest enclosing dataset supplies context when no local value exists.
    /// Parents are indexed before children, but may contain metadata after a SQ;
    /// resolving after parsing avoids ordering assumptions and sibling leakage.
    func resolveImplicitContextualVR() -> DICOMParserOutcome<Void> {
        precondition(!state.pointee.sealed)
        guard state.pointee.hasContextualVR else { return .success(()) }
        for identifier in 1..<scopes.count {
            if let failure = cancellation.failure { return .failure(.managed(failure)) }
            var scope = scopes[identifier]
            if scope.pixelRepresentation == .absent && scope.parent >= 1 {
                scope.pixelRepresentation = scopes[scope.parent].pixelRepresentation
                state.pointee.scopes[identifier] = scope
            }
            let isModalityLUTItem = scope.sequenceElement >= 0
                && elements[scope.sequenceElement].tag == Tag(group: 0x0028, element: 0x3000)
            var node = scope.firstElement
            while node >= 0 {
                if let failure = cancellation.failure { return .failure(.managed(failure)) }
                let element = elements[node]
                let isPadding = Self.isPixelPadding(element.tag)
                let isModalityDescriptor = isModalityLUTItem
                    && element.tag == Tag(group: 0x0028, element: 0x3002)
                if isPadding || isModalityDescriptor {
                    guard element.length == (isPadding ? 2 : 6) else {
                        return .failure(.malformed(offset: element.range.lowerBound,
                            reason: isPadding ? .pixelPaddingLength : .modalityLUTDescriptorLength))
                    }
                    let vr: VR
                    switch scope.pixelRepresentation {
                    case .unsigned: vr = .US
                    case .signed: vr = .SS
                    case .absent, .invalid:
                        return .failure(.malformed(offset: element.range.lowerBound,
                            reason: isPadding ? .pixelPaddingRepresentation : .modalityLUTDescriptorRepresentation))
                    }
                    state.pointee.elements[node].vr = vr
                } else if element.tag == Tag(group: 0x0028, element: 0x3006) {
                    // PS3.5 A.1 permits US or OW. Choose OW for implicit data so
                    // packed 8-bit values are not mistaken for scalar US words.
                    // The raw value, including any padding, remains untouched.
                    state.pointee.elements[node].vr = .OW
                }
                node = element.nextSibling
            }
        }
        return .success(())
    }
    func append(tag: Tag, vr: VR, length: UInt32, byteOrder: ByteOrder, range: Range<Int>) -> DICOMParserOutcome<Int> {
        precondition(!state.pointee.sealed)
        let identifier = elements.count
        if case .failure(let failure) = state.pointee.elements.appendOutcome(
            Element(tag: tag, length: length, byteOrder: byteOrder, vr: vr, range: range)) {
            return .failure(.managed(DICOMManagedFailure(allocation: failure)))
        }
        var scope = scopes[currentScope]
        if scope.lastElement >= 0 { state.pointee.elements[scope.lastElement].nextSibling = identifier }
        else { scope.firstElement = identifier }
        scope.lastElement = identifier; scope.elementCount += 1; state.pointee.scopes[currentScope] = scope
        if Self.isPixelPadding(tag) || tag == Tag(group: 0x0028, element: 0x3002)
            || tag == Tag(group: 0x0028, element: 0x3006) {
            state.pointee.hasContextualVR = true
        }
        return .success(identifier)
    }
    func beginItem() -> DICOMParserOutcome<Int> {
        precondition(!state.pointee.sealed && currentSequence >= 0)
        let previous = currentScope, identifier = scopes.count
        if case .failure(let failure) = state.pointee.scopes.appendOutcome(
            Scope(parent: previous, sequenceElement: currentSequence)) {
            return .failure(.managed(DICOMManagedFailure(allocation: failure)))
        }
        var sequence = elements[currentSequence]
        if sequence.lastItem >= 0 { state.pointee.scopes[sequence.lastItem].nextItem = identifier }
        else { sequence.firstItem = identifier }
        sequence.lastItem = identifier; sequence.itemCount += 1
        state.pointee.elements[currentSequence] = sequence; currentScope = identifier
        return .success(previous)
    }
    func setRange(_ range: Range<Int>, for identifier: Int) { state.pointee.elements[identifier].range = range }
    func setBOT(_ range: Range<Int>, for identifier: Int) { state.pointee.elements[identifier].botRange = range }
    func appendFragment(_ range: Range<Int>, streamOffset: Int, to identifier: Int) -> DICOMParserOutcome<Void> {
        if elements[identifier].firstFragment < 0 { state.pointee.elements[identifier].firstFragment = fragments.count }
        if case .failure(let failure) = state.pointee.fragments.appendOutcome(
            Fragment(range: range, streamOffset: streamOffset)) {
            return .failure(.managed(DICOMManagedFailure(allocation: failure)))
        }
        state.pointee.elements[identifier].fragmentCount += 1
        return .success(())
    }
    func record(_ tag: Tag, at offset: Int) -> DICOMParserOutcome<Void> {
        let key = UInt32(tag.group) << 16 | UInt32(tag.element)
        if state.pointee.membership.count == 0 || state.pointee.membershipCount >= state.pointee.membership.count / 2 {
            if case .failure(let failure) = growMembership() { return .failure(failure) }
        }
        let slot = find(scope: currentScope, tag: key, in: state.pointee.membership)
        guard state.pointee.membership[slot].scope < 0 else {
            return .failure(.strict(.duplicateTag(tag: tag, offset: offset)))
        }
        state.pointee.membership[slot] = Membership(scope: currentScope, tag: key)
        state.pointee.membershipCount += 1
        return .success(())
    }
    private func find(scope: Int, tag: UInt32, in table: borrowing DICOMStorageVector<Membership>) -> Int {
        var bits = (UInt64(scope) << 32 | UInt64(tag)) &* 0x9e3779b97f4a7c15
        bits ^= bits >> 32
        var slot = Int(bits & UInt64(table.count - 1))
        while table[slot].scope >= 0 && (table[slot].scope != scope || table[slot].tag != tag) {
            slot = (slot + 1) & (table.count - 1)
        }
        return slot
    }
    private func growMembership() -> DICOMParserOutcome<Void> {
        let count = state.pointee.membership.count
        let (capacity, overflow) = max(512, count).multipliedReportingOverflow(by: count == 0 ? 1 : 2)
        guard !overflow else { return .failure(.managed(DICOMManagedFailure(allocation: .invalidSize))) }
        var allocationFailure = DICOMAllocationError.invalidSize
        guard var next = DICOMStorageVector<Membership>.make(budget: state.pointee.budget)
            .takeValue(failure: &allocationFailure) else {
            return .failure(.managed(DICOMManagedFailure(allocation: allocationFailure)))
        }
        for _ in 0..<capacity {
            if case .failure(let failure) = next.appendOutcome(Membership()) {
                return .failure(.managed(DICOMManagedFailure(allocation: failure)))
            }
        }
        for index in 0..<count {
            let entry = state.pointee.membership[index]
            if entry.scope >= 0 { next[find(scope: entry.scope, tag: entry.tag, in: next)] = entry }
        }
        state.pointee.membership = consume next
        return .success(())
    }
}
#endif
