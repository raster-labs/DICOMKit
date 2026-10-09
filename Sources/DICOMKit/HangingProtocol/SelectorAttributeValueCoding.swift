// NEMA-verified: 2026a, checked 2026-09-29 — Selector Attribute value attributes per PS3.3 2026a C.23.4; Code Sequence Macro elements reused for Abstract Prior Code Sequence (0072,003E) items (Table C.23.1-1); CID 31 contents not compared
//
//  SelectorAttributeValueCoding.swift
//  DICOMKit
//
//  Encodes and decodes the Selector Attribute Value elements of the Hanging
//  Protocol Image Set Selector Macro.
//
//  Reference: PS3.3 Table C.23.4-1 (Image Set Selector Module),
//             PS3.6 Table 6-1 (0072,0050) and (0072,005E)–(0072,0083)
//

import Foundation
import DICOMCore
import DICOMDictionary

/// Maps a Selector Attribute VR (0072,0050) to its Selector *xx* Value element
/// and converts between `ImageSetSelector.values` and that element's encoding.
enum SelectorAttributeValueCoding {
    
    /// The Selector *xx* Value tag for a VR (PS3.6 (0072,005E)–(0072,0083)).
    static func valueTag(for vr: VR) -> Tag {
        switch vr {
        case .AE: return .selectorAEValue
        case .AS: return .selectorASValue
        case .AT: return .selectorATValue
        case .DA: return .selectorDAValue
        case .CS: return .selectorCSValue
        case .DT: return .selectorDTValue
        case .IS: return .selectorISValue
        case .OB: return .selectorOBValue
        case .LO: return .selectorLOValue
        case .OF: return .selectorOFValue
        case .LT: return .selectorLTValue
        case .OW: return .selectorOWValue
        case .PN: return .selectorPNValue
        case .TM: return .selectorTMValue
        case .SH: return .selectorSHValue
        case .UN: return .selectorUNValue
        case .ST: return .selectorSTValue
        case .UC: return .selectorUCValue
        case .UT: return .selectorUTValue
        case .UR: return .selectorURValue
        case .DS: return .selectorDSValue
        case .OD: return .selectorODValue
        case .FD: return .selectorFDValue
        case .OL: return .selectorOLValue
        case .FL: return .selectorFLValue
        case .UL: return .selectorULValue
        case .US: return .selectorUSValue
        case .SL: return .selectorSLValue
        case .SS: return .selectorSSValue
        case .UI: return .selectorUIValue
        case .SQ: return .selectorCodeSequenceValue
        case .OV: return .selectorOVValue
        case .SV: return .selectorSVValue
        case .UV: return .selectorUVValue
        }
    }
    
    /// The VR a Selector *xx* Value tag carries, or nil for any other tag.
    static func vr(forValueTag tag: Tag) -> VR? {
        VR.allCases.first { valueTag(for: $0) == tag }
    }
    
    /// The VR the data dictionary assigns to `tag`, for a selector that did
    /// not state one. Multi-VR entries (US/SS, OB/OW) resolve to the first.
    static func dictionaryVR(for tag: Tag) -> VR? {
        DataElementDictionary.lookup(tag: tag)?.vr.first
    }
    
    // MARK: - Encoding
    
    /// Builds the Selector *xx* Value element for `vr`.
    ///
    /// - Throws: `HangingProtocolError.invalidAttributeValue` when a value
    ///   cannot be represented in `vr` (a non-numeric US value, an odd-length
    ///   hex string, an AT value that is not a tag, an SQ selector without
    ///   code items).
    static func encode(values: [String], codeValues: [CodedConcept], vr: VR) throws -> DataElement {
        let tag = valueTag(for: vr)
        switch vr {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .PN, .SH, .TM, .UC, .UI, .UR:
            return DataElement.strings(tag: tag, vr: vr, values: values)
        case .LT, .ST, .UT:
            // VM 1; a backslash is part of the value, not a separator.
            return DataElement.string(tag: tag, vr: vr, value: values.joined(separator: "\\"))
        case .AT:
            return DataElement.attributeTags(tag: tag, values: try values.map { try parseTag($0) })
        case .US:
            return DataElement.uint16s(tag: tag, values: try values.map { try parseInteger($0, vr: vr) })
        case .SS:
            return DataElement.int16s(tag: tag, values: try values.map { try parseInteger($0, vr: vr) })
        case .UL:
            return DataElement.uint32s(tag: tag, values: try values.map { try parseInteger($0, vr: vr) })
        case .SL:
            return DataElement.int32s(tag: tag, values: try values.map { try parseInteger($0, vr: vr) })
        case .FL:
            return DataElement.float32s(tag: tag, values: try values.map { try parseFloat($0, vr: vr) })
        case .FD:
            return DataElement.float64s(tag: tag, values: try values.map { try parseFloat($0, vr: vr) })
        case .SV:
            let ints: [Int64] = try values.map { try parseInteger($0, vr: vr) }
            return rawElement(tag: tag, vr: vr, data: littleEndianData(ints.map { UInt64(bitPattern: $0) }))
        case .UV:
            let ints: [UInt64] = try values.map { try parseInteger($0, vr: vr) }
            return rawElement(tag: tag, vr: vr, data: littleEndianData(ints))
        case .OB, .OW, .OD, .OF, .OL, .OV, .UN:
            var data = Data()
            for value in values { data.append(try parseHex(value, vr: vr)) }
            return rawElement(tag: tag, vr: vr, data: data)
        case .SQ:
            guard !codeValues.isEmpty else {
                throw HangingProtocolError.invalidAttributeValue(
                    "an SQ selector needs codeValues for Selector Code Sequence Value (0072,0080)")
            }
            let items = codeValues.map { SequenceItem(elements: codeElements($0)) }
            return sequenceElement(tag: tag, items: items)
        }
    }
    
    // MARK: - Decoding
    
    /// Reads `element` back into selector values and code items according
    /// to the element's own VR, so a Selector *xx* Value decodes the same
    /// way whether or not (0072,0050) accompanied it.
    static func decode(_ element: DataElement) -> (values: [String], codeValues: [CodedConcept]) {
        switch element.vr {
        case .AE, .AS, .CS, .DA, .DS, .DT, .IS, .LO, .PN, .SH, .TM, .UC, .UI, .UR:
            return (element.stringValues ?? [], [])
        case .LT, .ST, .UT:
            return (element.stringValue.map { [$0] } ?? [], [])
        case .AT:
            return ((element.attributeTagValues ?? []).map(\.description), [])
        case .US:
            return ((element.uint16Values ?? []).map(String.init), [])
        case .SS:
            return ((element.int16Values ?? []).map(String.init), [])
        case .UL:
            return ((element.uint32Values ?? []).map(String.init), [])
        case .SL:
            return ((element.int32Values ?? []).map(String.init), [])
        case .FL:
            return ((element.float32Values ?? []).map { String($0) }, [])
        case .FD:
            return ((element.float64Values ?? []).map { String($0) }, [])
        case .SV:
            return (littleEndianUInt64s(element.valueData).map { String(Int64(bitPattern: $0)) }, [])
        case .UV:
            return (littleEndianUInt64s(element.valueData).map(String.init), [])
        case .OB, .OW, .OD, .OF, .OL, .OV, .UN:
            return (element.valueData.isEmpty ? [] : [hexString(element.valueData)], [])
        case .SQ:
            let codes = (element.sequenceItems ?? []).compactMap(codedConcept(from:))
            return (codes.map(\.codeValue), codes)
        }
    }
    
    // MARK: - Helpers
    
    /// Accepts "(GGGG,EEEE)", "GGGG,EEEE" and "GGGGEEEE".
    static func parseTag(_ text: String) throws -> Tag {
        let hex = text.filter { $0.isHexDigit }
        guard hex.count == 8, text.filter({ !$0.isHexDigit && !"(),".contains($0) }).isEmpty,
              let group = UInt16(hex.prefix(4), radix: 16),
              let element = UInt16(hex.suffix(4), radix: 16) else {
            throw HangingProtocolError.invalidAttributeValue("'\(text)' is not a tag for Selector AT Value")
        }
        return Tag(group: group, element: element)
    }
    
    private static func parseInteger<T: FixedWidthInteger>(_ text: String, vr: VR) throws -> T {
        guard let value = T(text.trimmingCharacters(in: .whitespaces)) else {
            throw HangingProtocolError.invalidAttributeValue("'\(text)' is not a \(vr.rawValue) value")
        }
        return value
    }
    
    private static func parseFloat<T: BinaryFloatingPoint & LosslessStringConvertible>(_ text: String, vr: VR) throws -> T {
        guard let value = T(text.trimmingCharacters(in: .whitespaces)) else {
            throw HangingProtocolError.invalidAttributeValue("'\(text)' is not a \(vr.rawValue) value")
        }
        return value
    }
    
    private static func parseHex(_ text: String, vr: VR) throws -> Data {
        let hex = Array(text.filter { !$0.isWhitespace })
        guard hex.count % 2 == 0 else {
            throw HangingProtocolError.invalidAttributeValue("'\(text)' is not even-length hex for \(vr.rawValue)")
        }
        var data = Data(capacity: hex.count / 2)
        for index in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(hex[index...index + 1]), radix: 16) else {
                throw HangingProtocolError.invalidAttributeValue("'\(text)' is not hex for \(vr.rawValue)")
            }
            data.append(byte)
        }
        return data
    }
    
    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
    
    private static func littleEndianData(_ values: [UInt64]) -> Data {
        var data = Data(capacity: values.count * 8)
        for value in values {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
    
    private static func littleEndianUInt64s(_ data: Data) -> [UInt64] {
        stride(from: 0, to: data.count - data.count % 8, by: 8).map { offset in
            data[data.startIndex + offset ..< data.startIndex + offset + 8]
                .enumerated()
                .reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
        }
    }
    
    private static func rawElement(tag: Tag, vr: VR, data: Data) -> DataElement {
        DataElement(tag: tag, vr: vr, length: UInt32(data.count), valueData: data)
    }
    
    private static func sequenceElement(tag: Tag, items: [SequenceItem]) -> DataElement {
        let writer = DICOMWriter()
        var data = Data()
        for item in items { data.append(writer.serializeSequenceItem(item)) }
        return DataElement(tag: tag, vr: .SQ, length: UInt32(data.count), valueData: data, sequenceItems: items)
    }
    
    /// Code Sequence Macro (PS3.3 Table 8.8-1) elements for one item.
    static func codeElements(_ code: CodedConcept) -> [DataElement] {
        var elements = [
            DataElement.string(tag: .codeValue, vr: .SH, value: code.codeValue),
            DataElement.string(tag: .codingSchemeDesignator, vr: .SH, value: code.codingSchemeDesignator),
            DataElement.string(tag: .codeMeaning, vr: .LO, value: code.codeMeaning),
        ]
        if let version = code.codingSchemeVersion {
            elements.append(DataElement.string(tag: .codingSchemeVersion, vr: .SH, value: version))
        }
        if let long = code.longCodeValue {
            elements.append(DataElement.string(tag: .longCodeValue, vr: .UC, value: long))
        }
        if let urn = code.urnCodeValue {
            elements.append(DataElement.string(tag: .urnCodeValue, vr: .UR, value: urn))
        }
        return elements
    }
    
    static func codedConcept(from item: SequenceItem) -> CodedConcept? {
        guard let designator = item.string(for: .codingSchemeDesignator) else { return nil }
        let value = item.string(for: .codeValue)
            ?? item.string(for: .longCodeValue)
            ?? item.string(for: .urnCodeValue)
        guard let codeValue = value else { return nil }
        return CodedConcept(
            codeValue: codeValue,
            codingSchemeDesignator: designator,
            codeMeaning: item.string(for: .codeMeaning) ?? "",
            codingSchemeVersion: item.string(for: .codingSchemeVersion),
            longCodeValue: item.string(for: .longCodeValue),
            urnCodeValue: item.string(for: .urnCodeValue))
    }
}
