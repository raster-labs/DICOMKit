// NEMA-verified: 2026a, checked 2026-09-29 — PS3.3 2026a C.11.1.1 and C.11.2.1.1 LUT Descriptor semantics; the 8...16 bits-per-entry tolerance and output normalisation are recorded
// NEMA-verified: 2026a, checked 2026-09-30 — normalized(_:) divides by 2^n − 1 (n = third LUT Descriptor value) per PS3.3 2026a C.11.2.1.1 "The output range is from 0 to 2^n-1"; used-range scaling is an explicit opt-in (D53)
// NEMA-verified: 2026a, checked 2026-09-30 — entry(for:) clamps to the first/last entry per PS3.3 2026a C.11.1.1.1 before the index conversion, so NaN (first entry) and ±infinity (first/last) no longer trap (D54)
// GrayscaleLUT.swift
// DICOMKit
//
// Table-form grayscale LUTs: the Modality LUT Sequence (0028,3000) and the
// VOI LUT Sequence (0028,3010). Both share one wire structure — LUT Descriptor
// (three US/SS values) plus LUT Data (US or OW) — so both decode into this one
// type; what differs is how the entries are *used*, which the two apply
// methods make explicit.
//
// Before this existed, an image whose correct presentation requires a table
// LUT printed with the linear rescale or window instead — silently, and with
// the wrong contrast (SRS FR-004).
//
// Reference: PS3.3 C.11.1 (Modality LUT), C.11.2 (VOI LUT).

import Foundation
import DICOMCore

/// One decoded grayscale lookup table.
public struct GrayscaleLUT: Sendable, Equatable {

    /// The first input value the table maps. Inputs below clamp to the first
    /// entry, inputs past the end clamp to the last (PS3.3 C.11.1.1).
    public let firstMappedValue: Int

    /// Bits per entry as declared (8 or 16).
    public let bitsPerEntry: Int

    /// The table. Never empty.
    public let entries: [UInt16]

    /// LUT Explanation (0028,3003), when the file carries one.
    public let explanation: String?

    /// The smallest and largest entry, precomputed for normalization.
    public let entryRange: ClosedRange<Double>

    public init?(firstMappedValue: Int, bitsPerEntry: Int, entries: [UInt16],
                 explanation: String? = nil) {
        guard !entries.isEmpty else { return nil }
        self.firstMappedValue = firstMappedValue
        self.bitsPerEntry = bitsPerEntry
        self.entries = entries
        self.explanation = explanation
        var low = Double(entries[0]), high = Double(entries[0])
        for entry in entries {
            low = min(low, Double(entry))
            high = max(high, Double(entry))
        }
        self.entryRange = low...high
    }

    // MARK: Decoding

    /// Decodes one LUT sequence item.
    ///
    /// The classic failure points, handled here so no caller re-learns them:
    /// - Descriptor value 1 (number of entries) of **0 means 65536**, not zero.
    /// - Descriptor value 2 (first mapped value) is **signed** when the
    ///   image's Pixel Representation is 1.
    /// - LUT Data may be US or OW; 8-bit entries may be packed one per byte
    ///   or one per 16-bit word.
    public static func parse(item: SequenceItem, signedPixels: Bool) -> GrayscaleLUT? {
        guard let descriptorData = item[.lutDescriptor]?.valueData,
              descriptorData.count >= 6 else { return nil }

        let declaredEntries = Int(descriptorData.readUInt16LE(at: 0) ?? 0)
        let numberOfEntries = declaredEntries == 0 ? 65536 : declaredEntries
        let rawFirst = descriptorData.readUInt16LE(at: 2) ?? 0
        let firstMapped = signedPixels ? Int(Int16(bitPattern: rawFirst)) : Int(rawFirst)
        let bitsPerEntry = Int(descriptorData.readUInt16LE(at: 4) ?? 0)
        guard bitsPerEntry >= 8, bitsPerEntry <= 16 else { return nil }

        guard let lutData = item[.lutData]?.valueData else { return nil }

        var entries: [UInt16] = []
        entries.reserveCapacity(numberOfEntries)
        if bitsPerEntry == 8, lutData.count >= numberOfEntries,
           lutData.count < numberOfEntries * 2 {
            // One entry per byte.
            for index in 0..<numberOfEntries {
                entries.append(UInt16(lutData[lutData.startIndex + index]))
            }
        } else if lutData.count >= numberOfEntries * 2 {
            // One entry per little-endian 16-bit word (US or OW).
            for index in 0..<numberOfEntries {
                guard let value = lutData.readUInt16LE(at: index * 2) else { return nil }
                entries.append(value)
            }
        } else {
            return nil
        }

        return GrayscaleLUT(
            firstMappedValue: firstMapped,
            bitsPerEntry: bitsPerEntry,
            entries: entries,
            explanation: item.string(for: .lutExplanation)?
                .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Lookup

    /// The entry a (possibly fractional) input value maps to, clamped to the
    /// table's ends per PS3.3 C.11.1.1.1: below the first mapped value (and
    /// -infinity) to the first entry, past the end (and +infinity) to the last.
    /// NaN maps to the first entry.
    public func entry(for input: Double) -> UInt16 {
        // Clamp before converting to an index: Int(_:) traps on NaN, ±infinity and
        // magnitudes beyond Int (D54).
        let offset = (input - Double(firstMappedValue)).rounded()
        guard !offset.isNaN, offset > 0 else { return entries[0] }
        guard offset < Double(entries.count - 1) else { return entries[entries.count - 1] }
        return entries[Int(offset)]
    }

    /// A Modality LUT lookup: the raw entry value, in the manufacturer-defined
    /// output units the table's Modality LUT Type / Explanation describe.
    public func value(for input: Double) -> Double {
        Double(entry(for: input))
    }

    /// A VOI LUT lookup, normalized to 0…1.
    ///
    /// By default the output range is 0…2^n − 1 with n the third LUT
    /// Descriptor value (`bitsPerEntry`), per PS3.3 2026a C.11.2.1.1: "The
    /// output range is from 0 to 2^n-1 where n is the third Value of LUT
    /// Descriptor." A 16-bit table whose entries stop at 4095 therefore peaks
    /// at 4095/65535, and a flat table returns its entry over 2^n − 1.
    ///
    /// - Parameter normalizeToUsedRange: `true` opts in to the non-standard
    ///   print tolerance (SRS FR-004): divide over the span the entries
    ///   actually use (`entryRange`) instead, so a 12-bit table declared as
    ///   16 bits per entry fills the film; a flat table then returns 0. A
    ///   table that reaches 0 and 2^n − 1 gives the same result either way.
    ///   `ImagePreprocessor.prepareForPrint` passes `true` (D53).
    public func normalized(_ input: Double, normalizeToUsedRange: Bool = false) -> Double {
        let value = Double(entry(for: input))
        guard normalizeToUsedRange else {
            // `init` does not range-check `bitsPerEntry`; entries are 16-bit,
            // so n is clamped to 1...16 to keep the divisor positive.
            let bits = min(max(bitsPerEntry, 1), 16)
            return value / Double((1 << bits) - 1)
        }
        let span = entryRange.upperBound - entryRange.lowerBound
        guard span > 0 else { return 0 }
        return (value - entryRange.lowerBound) / span
    }
}

// MARK: - Reading from a data set

public extension DataSet {

    /// The image's Modality LUT Sequence (0028,3000) table, when it has one.
    ///
    /// PS3.3 C.11.1: the sequence and Rescale Slope/Intercept are mutually
    /// exclusive — when this returns a table, the rescale pair **must not**
    /// also be applied.
    func modalityLUT() -> GrayscaleLUT? {
        guard let item = self[Tag(group: 0x0028, element: 0x3000)]?
            .sequenceItems?.first else { return nil }
        return GrayscaleLUT.parse(item: item, signedPixels: isSignedPixelData)
    }

    /// The image's first VOI LUT Sequence (0028,3010) table, when it has one.
    ///
    /// The first item is the default presentation, exactly as the first
    /// Window Center value is (PS3.3 C.11.2). Its input is the Modality LUT's
    /// output, so its first mapped value is signed whenever that output can be
    /// negative (C.11.2.1.1): a table-form Modality LUT never is, a rescale
    /// with a negative intercept (CT's −1024) always is, and bare stored
    /// pixels are when Pixel Representation says so.
    func voiLUT() -> GrayscaleLUT? {
        guard let item = self[Tag(group: 0x0028, element: 0x3010)]?
            .sequenceItems?.first else { return nil }
        let signed: Bool
        if modalityLUT() != nil {
            signed = false
        } else if rescaleSlope() != 1 || rescaleIntercept() != 0 {
            signed = rescaleIntercept() < 0 || (rescaleSlope() < 0)
                || isSignedPixelData
        } else {
            signed = isSignedPixelData
        }
        return GrayscaleLUT.parse(item: item, signedPixels: signed)
    }

    /// Whether Pixel Representation (0028,0103) declares signed pixels.
    private var isSignedPixelData: Bool {
        uint16(for: Tag(group: 0x0028, element: 0x0103)) == 1
    }
}
