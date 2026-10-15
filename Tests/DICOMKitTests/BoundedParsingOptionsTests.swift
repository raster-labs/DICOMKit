import Testing
@testable import DICOMKit

@Suite("Scalar bounded parsing policy")
struct BoundedParsingOptionsTests {
    @Test("Every finite allowlist preserves the legacy strict policy", arguments: UInt8(0)...UInt8(31))
    func finiteMaskParity(mask: UInt8) throws {
        var allowed: Set<String> = []
        for raw in UInt8(0)...UInt8(4) {
            let syntax = try #require(BoundedTransferSyntax(rawValue: raw))
            if mask & syntax.mask != 0 { allowed.insert(syntax.uid) }
        }
        let legacy = try BoundedParsingOptions(ParsingOptions(maxElements: 17, maxSequenceDepth: 9,
            maxElementLength: 23, maxTotalElements: 31, maxFragmentCount: 7,
            maximumInflatedByteCount: 53, strictEncapsulation: true, maximumEncapsulatedBytes: 41,
            allowedTransferSyntaxUIDs: allowed, validationPolicy: .strict))
        let scalar = try #require(BoundedParsingOptions.make(allowedTransferSyntaxMask: mask,
            maxElements: 17, maxSequenceDepth: 9, maxElementLength: 23, maxTotalElements: 31,
            maxFragmentCount: 7, strictEncapsulation: true, maximumEncapsulatedBytes: 41,
            maximumInflatedByteCount: 53))
        #expect(scalar.validationPolicy == .strict && scalar.mode == .full && scalar.stopAfterTag == nil)
        #expect(scalar.allowedTransferSyntaxMask == legacy.allowedTransferSyntaxMask)
        #expect(scalar.maxElements == legacy.maxElements)
        #expect(scalar.maxSequenceDepth == legacy.maxSequenceDepth)
        #expect(scalar.maxElementLength == legacy.maxElementLength)
        #expect(scalar.maxTotalElements == legacy.maxTotalElements)
        #expect(scalar.maxFragmentCount == legacy.maxFragmentCount)
        #expect(scalar.strictEncapsulation == legacy.strictEncapsulation)
        #expect(scalar.maximumEncapsulatedBytes == legacy.maximumEncapsulatedBytes)
        #expect(scalar.maximumInflatedByteCount == legacy.maximumInflatedByteCount)
        #expect(scalar.strictResourceLimits == legacy.strictResourceLimits)
    }

    @Test("Unknown bits and existing strict option refusals remain closed")
    func refusals() {
        for mask: UInt8 in [0x20, 0x40, 0x80, 0xff] {
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: mask,
                strictEncapsulation: true) == nil)
        }
        for maximum in [-1, 0] {
            #expect(BoundedParsingOptions.make(maxElements: maximum) == nil)
            #expect(throws: StrictParsingError.invalidOptions) {
                try BoundedParsingOptions(ParsingOptions(maxElements: maximum, validationPolicy: .strict))
            }
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: 0x1f,
                maxFragmentCount: maximum, strictEncapsulation: true) == nil)
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: 0x1f,
                strictEncapsulation: true, maximumEncapsulatedBytes: maximum) == nil)
        }
        #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: 0x1f) == nil)
        for invalid in 0..<5 {
            let limits = ParsingOptions.StrictResourceLimits(maximumInputBytes: invalid == 0 ? 0 : 1,
                maximumSequenceDepth: invalid == 1 ? 0 : 1, maximumTotalElements: invalid == 2 ? 0 : 1,
                maximumSequenceItems: invalid == 3 ? 0 : 1,
                maximumMaterializedValueBytes: invalid == 4 ? 0 : 1)
            #expect(BoundedParsingOptions.make(strictResourceLimits: limits) == nil)
            #expect(throws: StrictParsingError.invalidOptions) {
                try BoundedParsingOptions(ParsingOptions(validationPolicy: .strict, strictResourceLimits: limits))
            }
        }
    }

    @Test("Legacy negative optional caps and empty allowlist preserve their existing meaning")
    func retainedCaps() throws {
        let legacy = try BoundedParsingOptions(ParsingOptions(maxSequenceDepth: -1, maxElementLength: -1,
            maxTotalElements: -1, maxFragmentCount: -1, maximumInflatedByteCount: -1,
            maximumEncapsulatedBytes: -1, allowedTransferSyntaxUIDs: [], validationPolicy: .strict))
        let scalar = try #require(BoundedParsingOptions.make(allowedTransferSyntaxMask: 0,
            maxSequenceDepth: -1, maxElementLength: -1, maxTotalElements: -1, maxFragmentCount: -1,
            maximumEncapsulatedBytes: -1, maximumInflatedByteCount: -1))
        #expect(scalar.allowedTransferSyntaxMask == 0 && legacy.allowedTransferSyntaxMask == 0)
        #expect(scalar.maxSequenceDepth == legacy.maxSequenceDepth)
        #expect(scalar.maxElementLength == legacy.maxElementLength)
        #expect(scalar.maxTotalElements == legacy.maxTotalElements)
        #expect(scalar.maxFragmentCount == legacy.maxFragmentCount)
        #expect(scalar.maximumEncapsulatedBytes == legacy.maximumEncapsulatedBytes)
        #expect(scalar.maximumInflatedByteCount == legacy.maximumInflatedByteCount)
        let defaults = try #require(BoundedParsingOptions.make())
        #expect(defaults.allowedTransferSyntaxMask == 0x03)
    }
}
