import Testing
@testable import DICOMKit

@Suite("Scalar bounded parsing policy")
struct BoundedParsingOptionsTests {
    private static let sampleMasks: [UInt32] = {
        var masks: [UInt32] = [
            0,
            BoundedTransferSyntax.nativeMask,
            0x1F,
            BoundedTransferSyntax.compressedMask,
            BoundedTransferSyntax.allSupportedMask
        ]
        for syntax in BoundedTransferSyntax.allCases {
            masks.append(syntax.mask)
            masks.append(BoundedTransferSyntax.nativeMask | syntax.mask)
        }
        return Array(Set(masks)).sorted()
    }()

    @Test("BoundedTransferSyntax enumerates all 17 strict syntaxes with contiguous masks")
    func syntaxMasks() {
        #expect(BoundedTransferSyntax.allCases.count == 17)
        #expect(BoundedTransferSyntax.nativeMask == 0x03)
        #expect(BoundedTransferSyntax.compressedMask == 0x0001_FFFC)
        #expect(BoundedTransferSyntax.allSupportedMask == 0x0001_FFFF)
        let compressedUIDs = Set(BoundedTransferSyntax.allCases.filter(\.isCompressed).map(\.uid))
        #expect(compressedUIDs == ParsingOptions.strictCompressedTransferSyntaxUIDs)
    }

    @Test("Every finite allowlist preserves the legacy strict policy", arguments: BoundedParsingOptionsTests.sampleMasks)
    func finiteMaskParity(mask: UInt32) throws {
        var allowed: Set<String> = []
        for syntax in BoundedTransferSyntax.allCases {
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
        for mask: UInt32 in [0x0002_0000, 0x0004_0000, 0x8000_0000, UInt32.max] {
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: mask,
                strictEncapsulation: true) == nil)
        }
        for syntax in BoundedTransferSyntax.allCases where syntax.isCompressed {
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: syntax.mask,
                strictEncapsulation: false) == nil)
        }
        for maximum in [-1, 0] {
            #expect(BoundedParsingOptions.make(maxElements: maximum) == nil)
            #expect(throws: StrictParsingError.invalidOptions) {
                try BoundedParsingOptions(ParsingOptions(maxElements: maximum, validationPolicy: .strict))
            }
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: BoundedTransferSyntax.allSupportedMask,
                maxFragmentCount: maximum, strictEncapsulation: true) == nil)
            #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: BoundedTransferSyntax.allSupportedMask,
                strictEncapsulation: true, maximumEncapsulatedBytes: maximum) == nil)
        }
        #expect(BoundedParsingOptions.make(allowedTransferSyntaxMask: BoundedTransferSyntax.allSupportedMask) == nil)
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
