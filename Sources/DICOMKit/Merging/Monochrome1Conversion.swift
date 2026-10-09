// NEMA-verified: 2026a, checked 2026-09-30 — MONOCHROME2-only targets per PS3.3 2026a C.8.15.2 (Enhanced CT, Enumerated Value MONOCHROME2), A.36.2.3.1 (Enhanced MR), C.8.22.3 (Enhanced PET), A.70.3.1 / A.71.3.1 (Legacy Converted Enhanced CT / MR: "lossless conversion of the pixel data to MONOCHROME2 and updating of any related Attributes is necessary"), A.72.3.1 (Legacy Converted Enhanced PET), A.8.2.4 / A.8.3.4 / A.8.4.4 (Multi-frame Single Bit / Grayscale Byte / Grayscale Word SC: "shall be MONOCHROME2"); Enhanced XA/XRF (C.8.19.2) allows MONOCHROME1 and is not converted; MONOCHROME1/2 meaning per C.7.6.3.1.2; window functions per C.11.2.1.2.1 (LINEAR), C.11.2.1.3.1 (SIGMOID), C.11.2.1.3.2 (LINEAR_EXACT); VOI LUT Descriptor and Data per C.11.2.1.1; Presentation LUT Shape IDENTITY for MONOCHROME2 per A.8.3.4 / C.8.13.1
import Foundation
import DICOMCore

/// Lossless MONOCHROME1 → MONOCHROME2 conversion for merge targets that allow only
/// MONOCHROME2 (D37 c)
///
/// PS3.3 2026a C.7.6.3.1.2: in MONOCHROME1 "the minimum sample value is intended to be
/// displayed as white", in MONOCHROME2 as black, in both cases "after any VOI gray scale
/// transformations". The conversion therefore keeps the displayed picture:
///
/// - Stored values: every stored value `v` becomes `K - v`, where `K` is the sum of the
///   smallest and largest stored value (2^BitsStored - 1 unsigned, -1 two's complement).
///   Both are the bitwise complement of the Bits Stored bits, so the conversion is an
///   exact involution — lossless, as A.70.3.1 and A.71.3.1 require.
/// - Rescale Slope and Intercept are kept, so a rescaled value `y` becomes `C - y` with
///   `C = slope × K + 2 × intercept`. The window then moves to keep every VOI output
///   mirrored (the MONOCHROME1 inversion now happens in the data): Window Center `c`
///   becomes `C - c + 1` for LINEAR (C.11.2.1.2.1, whose formula centres on `c - 0.5` over
///   `w - 1`) and `C - c` for LINEAR_EXACT and SIGMOID (C.11.2.1.3.2, C.11.2.1.3.1); Window
///   Width is unchanged. A VOI LUT Sequence table is reversed, each entry complemented
///   within its bits, and its first input value mapped moved to `C - (first + n - 1)`
///   (C.11.2.1.1).
/// - Pixel Padding Value / Range Limit and the Smallest / Largest (Image / Series) Pixel
///   Values are stored values, so they map through `K - v` (smallest and largest swap).
/// - Presentation LUT Shape, if present, becomes IDENTITY — the inversion INVERSE
///   described is now in the data, and the MONOCHROME2 targets allow only IDENTITY.
///
/// Not converted, reported as ``Failure``: encapsulated (compressed) pixel data — the
/// codestream would have to be re-encoded; decoding with `--pixel-handling decode` makes
/// it native — and a Modality LUT Sequence, whose output range has no pivot to mirror.
enum Monochrome1Conversion {

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Targets whose Photometric Interpretation must be MONOCHROME2 (see file header)
    static func requiresMonochrome2(targetUID: String) -> Bool {
        typealias U = MultiframeSOPClassMap.UID
        return [
            U.enhancedCT, U.enhancedMR, U.enhancedPET,
            U.legacyConvertedEnhancedCT, U.legacyConvertedEnhancedMR, U.legacyConvertedEnhancedPET,
            U.multiframeSingleBitSC, U.multiframeGrayscaleByteSC, U.multiframeGrayscaleWordSC,
        ].contains(targetUID)
    }

    /// `K`: the sum of the smallest and largest stored value; `v` maps to `K - v`
    static func pivot(bitsStored: Int, isSigned: Bool) -> Int {
        isSigned ? -1 : (1 << bitsStored) - 1
    }

    // MARK: - Pixel data

    /// Complements the Bits Stored bits of every sample of a native frame
    static func invert(_ payload: FramePixelPayload) throws -> FramePixelPayload {
        guard case .native(let bytes) = payload.storage else {
            throw Failure(description: "MONOCHROME1 pixel data must be converted to MONOCHROME2 for this target (PS3.3 A.70.3.1, A.8.3.4), which needs native pixels; the frames are encapsulated in \(payload.transferSyntaxUID) — use --pixel-handling decode")
        }
        let d = payload.descriptor
        let bigEndian = payload.transferSyntaxUID == "1.2.840.10008.1.2.2"
        let lowBit = d.highBit + 1 - d.bitsStored
        guard d.bitsStored >= 1, lowBit >= 0, d.highBit < d.bitsAllocated else {
            throw Failure(description: "Bits Stored \(d.bitsStored) / High Bit \(d.highBit) do not fit Bits Allocated \(d.bitsAllocated)")
        }
        let storedMask = UInt64((1 << d.bitsStored) - 1) << UInt64(lowBit)
        var out = bytes
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            switch d.bitsAllocated {
            case 1:
                // Bit-packed single-bit frames (byte-aligned when extracted): every bit is a pixel
                for i in raw.indices { raw[i] ^= 0xFF }
            case 8:
                let mask = UInt8(truncatingIfNeeded: storedMask)
                for i in raw.indices { raw[i] ^= mask }
            case 16:
                let mask = UInt16(truncatingIfNeeded: storedMask)
                let (m0, m1) = bigEndian ? (UInt8(mask >> 8), UInt8(mask & 0xFF)) : (UInt8(mask & 0xFF), UInt8(mask >> 8))
                var i = raw.startIndex
                while i + 1 < raw.endIndex { raw[i] ^= m0; raw[i + 1] ^= m1; i += 2 }
            case 32:
                let mask = UInt32(truncatingIfNeeded: storedMask)
                let maskBytes = (0..<4).map { UInt8(truncatingIfNeeded: mask >> (8 * UInt32($0))) }
                let ordered = bigEndian ? Array(maskBytes.reversed()) : maskBytes
                var i = raw.startIndex
                while i + 3 < raw.endIndex {
                    for k in 0..<4 { raw[i + k] ^= ordered[k] }
                    i += 4
                }
            default:
                break
            }
        }
        guard [1, 8, 16, 32].contains(d.bitsAllocated) else {
            throw Failure(description: "cannot invert MONOCHROME1 samples of Bits Allocated \(d.bitsAllocated)")
        }
        let converted = PixelDataDescriptor(
            rows: d.rows, columns: d.columns, numberOfFrames: d.numberOfFrames,
            bitsAllocated: d.bitsAllocated, bitsStored: d.bitsStored, highBit: d.highBit,
            isSigned: d.isSigned, samplesPerPixel: d.samplesPerPixel,
            photometricInterpretation: .monochrome2,
            planarConfiguration: d.planarConfiguration)
        return FramePixelPayload(storage: .native(out), transferSyntaxUID: payload.transferSyntaxUID,
                                 descriptor: converted)
    }

    // MARK: - Related attributes

    /// Updates the attributes that describe stored or rescaled values (see type doc)
    static func convertAttributes(_ ds: inout DataSet, bitsStored: Int, isSigned: Bool) throws {
        if ds[.modalityLUTSequence] != nil {
            throw Failure(description: "MONOCHROME1 source with a Modality LUT Sequence (0028,3000) cannot be converted losslessly to MONOCHROME2 for this target (PS3.3 A.70.3.1)")
        }
        let k = pivot(bitsStored: bitsStored, isSigned: isSigned)
        let slope = decimal(ds, .rescaleSlope) ?? 1
        let intercept = decimal(ds, .rescaleIntercept) ?? 0
        let c = slope * Double(k) + 2 * intercept

        // Window Center (0028,1050), C.11.2.1.2.1 / C.11.2.1.3
        if let centers = ds.strings(for: .windowCenter), !centers.isEmpty {
            let function = ds.string(for: .voiLUTFunction)?.trimmingCharacters(in: .whitespaces) ?? "LINEAR"
            let offset = function == "LINEAR" || function.isEmpty ? 1.0 : 0.0
            let converted = try centers.map { text -> String in
                guard let center = Double(text.trimmingCharacters(in: .whitespaces)) else {
                    throw Failure(description: "Window Center value \"\(text)\" is not a number")
                }
                return DataSet.defaultDecimalString(c - center + offset)
            }
            ds.setStrings(converted, for: .windowCenter, vr: .DS)
        }

        // VOI LUT Sequence (0028,3010), C.11.2.1.1
        if let items = ds.sequence(for: .voiLUTSequence), !items.isEmpty {
            guard c == c.rounded(), abs(c) < 2_147_483_648.0 else {
                throw Failure(description: "VOI LUT Sequence cannot be mirrored: slope × K + 2 × intercept = \(c) is not an integer")
            }
            ds.setSequence(try items.map { try invertVOILUT($0, pivot: Int(c)) }, for: .voiLUTSequence)
        }

        // Stored-value attributes: v -> K - v
        for tag in [Tag.pixelPaddingValue, .pixelPaddingRangeLimit] {
            if let element = ds[tag], let value = integer(element) {
                ds[tag] = try integerElement(tag, vr: element.vr, value: k - value)
            }
        }
        for (smallestTag, largestTag) in [(Tag.smallestImagePixelValue, Tag.largestImagePixelValue),
                                          (.smallestPixelValueInSeries, .largestPixelValueInSeries)] {
            let smallest = ds[smallestTag]
            let largest = ds[largestTag]
            if let largest, let value = integer(largest) {
                ds[smallestTag] = try integerElement(smallestTag, vr: largest.vr, value: k - value)
            } else {
                ds[smallestTag] = nil
            }
            if let smallest, let value = integer(smallest) {
                ds[largestTag] = try integerElement(largestTag, vr: smallest.vr, value: k - value)
            } else {
                ds[largestTag] = nil
            }
        }

        if ds[.presentationLUTShape] != nil {
            ds.setString("IDENTITY", for: .presentationLUTShape, vr: .CS)
        }
        ds.setString(PhotometricInterpretation.monochrome2.rawValue, for: .photometricInterpretation, vr: .CS)
    }

    /// One VOI LUT Sequence Item mirrored about `pivot`: LUT'(x) = max − LUT(pivot − x)
    static func invertVOILUT(_ item: SequenceItem, pivot: Int) throws -> SequenceItem {
        guard let descriptorElement = item[.lutDescriptor], descriptorElement.valueData.count >= 6,
              let dataElement = item[.lutData] else {
            throw Failure(description: "VOI LUT Sequence Item without LUT Descriptor (0028,3002) and LUT Data (0028,3006)")
        }
        let raw = descriptorElement.valueData
        func word(_ i: Int) -> UInt16 {
            UInt16(raw[raw.startIndex + 2 * i]) | UInt16(raw[raw.startIndex + 2 * i + 1]) << 8
        }
        let count = word(0) == 0 ? 65536 : Int(word(0))
        let first = descriptorElement.vr == .SS ? Int(Int16(bitPattern: word(1))) : Int(word(1))
        let bits = Int(word(2))
        guard (1...16).contains(bits) else {
            throw Failure(description: "VOI LUT Descriptor has \(bits) bits per entry")
        }

        // Entries: 16-bit words, or one byte each when 8-bit entries are packed (C.11.2.1.1)
        let data = dataElement.valueData
        let packedBytes = bits == 8 && data.count < count * 2
        guard data.count >= (packedBytes ? count : count * 2) else {
            throw Failure(description: "VOI LUT Data holds fewer than \(count) entries")
        }
        let base = data.startIndex
        let entries: [Int] = (0..<count).map { i in
            packedBytes ? Int(data[base + i]) : Int(UInt16(data[base + 2 * i]) | UInt16(data[base + 2 * i + 1]) << 8)
        }
        let maxOut = (1 << bits) - 1
        let mirrored = entries.reversed().map { maxOut - min($0, maxOut) }

        let newFirst = pivot - (first + count - 1)
        let descriptorVR: VR = newFirst < 0 || descriptorElement.vr == .SS ? .SS : .US
        guard descriptorVR == .SS ? (-32768...32767).contains(newFirst) : (0...65535).contains(newFirst) else {
            throw Failure(description: "mirrored VOI LUT first input value \(newFirst) does not fit \(descriptorVR)")
        }
        var descriptorData = Data()
        for value in [UInt16(truncatingIfNeeded: count), UInt16(truncatingIfNeeded: newFirst), UInt16(bits)] {
            descriptorData.append(UInt8(value & 0xFF)); descriptorData.append(UInt8(value >> 8))
        }
        var lutData = Data()
        if packedBytes {
            lutData.append(contentsOf: mirrored.map { UInt8($0) })
            if lutData.count % 2 == 1 { lutData.append(0) }
        } else {
            for value in mirrored {
                lutData.append(UInt8(value & 0xFF)); lutData.append(UInt8(value >> 8))
            }
        }

        var elements = item.allElements.filter { $0.tag != .lutDescriptor && $0.tag != .lutData }
        elements.append(DataElement(tag: .lutDescriptor, vr: descriptorVR, length: UInt32(descriptorData.count), valueData: descriptorData))
        elements.append(DataElement(tag: .lutData, vr: dataElement.vr, length: UInt32(lutData.count), valueData: lutData))
        elements.sort { $0.tag < $1.tag }
        return SequenceItem(elements: elements)
    }

    // MARK: - Helpers

    private static func decimal(_ ds: DataSet, _ tag: Tag) -> Double? {
        ds.string(for: tag).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A US or SS value (the VR of these attributes follows Pixel Representation)
    private static func integer(_ element: DataElement) -> Int? {
        let data = element.valueData
        guard data.count >= 2 else { return nil }
        let word = UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
        return element.vr == .SS ? Int(Int16(bitPattern: word)) : Int(word)
    }

    private static func integerElement(_ tag: Tag, vr: VR, value: Int) throws -> DataElement {
        let fits = vr == .SS ? (-32768...32767).contains(value) : (0...65535).contains(value)
        guard fits else {
            throw Failure(description: "converted \(tag) value \(value) does not fit \(vr)")
        }
        let word = UInt16(truncatingIfNeeded: value)
        return DataElement(tag: tag, vr: vr == .SS ? .SS : .US, length: 2,
                           valueData: Data([UInt8(word & 0xFF), UInt8(word >> 8)]))
    }
}
