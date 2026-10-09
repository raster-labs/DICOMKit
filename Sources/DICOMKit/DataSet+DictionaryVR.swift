// NEMA-verified: 2026a, checked 2026-09-29 — the 17 string VRs are the character-string VRs of PS3.5 2026a Table 6.2-1; DS is at most 16 bytes; the VR of written elements comes from the DICOMDictionary
//
// DataSet+DictionaryVR.swift
// DICOMKit
//
// Writing an element means choosing a Value Representation, and until these
// existed every call site chose one by hand. Nothing compared those choices to
// the standard, so a wrong one survived until an external validator found it:
// the presentation-state builder wrote Image Rotation (0070,0042) as IS for
// years, which round-tripped perfectly through this library's own parser and
// was rejected by `dcmpschk` at the first attribute it checked.
//
// These setters take the VR from DICOMKit's own data dictionary instead, so the
// standard decides and the call site cannot disagree with it.
//

import Foundation
import DICOMCore
import DICOMDictionary

extension DataSet {

    // MARK: - Dictionary-Driven Setters

    /// Sets a string value using the VR the data dictionary gives the tag.
    ///
    /// Use this in preference to `setString(_:for:vr:)` for standard tags: it
    /// cannot be given a VR that disagrees with the standard.
    ///
    /// - Parameters:
    ///   - value: The string value to set.
    ///   - tag: The tag to set. Must be a standard tag with a text VR.
    /// - Returns: True when the element was written; false when the tag is not
    ///   in the dictionary, or its VR is binary and needs a typed setter.
    @discardableResult
    public mutating func setStringFromDictionary(_ value: String, for tag: Tag) -> Bool {
        guard let vr = Self.dictionaryVR(for: tag), vr.isStringRepresentable else {
            return false
        }
        self[tag] = DataElement.string(tag: tag, vr: vr, value: value)
        return true
    }

    /// Sets integer values, encoding them the way the dictionary's VR requires.
    ///
    /// The same number is a binary `US` for Image Rotation and an `IS` string
    /// for Graphic Layer Order; the caller supplies the number and the
    /// dictionary decides the encoding.
    ///
    /// - Parameters:
    ///   - values: The integer values to set.
    ///   - tag: The tag to set. Must be a standard tag with a numeric VR.
    /// - Returns: True when the element was written.
    @discardableResult
    public mutating func setIntegers(_ values: [Int], for tag: Tag) -> Bool {
        guard let vr = Self.dictionaryVR(for: tag) else { return false }
        switch vr {
        case .US:
            self[tag] = DataElement.uint16s(tag: tag, values: values.map { UInt16(clamping: $0) })
        case .SS:
            self[tag] = DataElement.int16s(tag: tag, values: values.map { Int16(clamping: $0) })
        case .UL:
            self[tag] = DataElement.uint32s(tag: tag, values: values.map { UInt32(clamping: $0) })
        case .SL:
            self[tag] = DataElement.int32s(tag: tag, values: values.map { Int32(clamping: $0) })
        case .IS:
            self[tag] = DataElement.strings(
                tag: tag, vr: .IS, values: values.map(String.init))
        case .DS:
            self[tag] = DataElement.strings(
                tag: tag, vr: .DS, values: values.map(String.init))
        case .FL:
            self[tag] = DataElement.float32s(tag: tag, values: values.map(Float32.init))
        case .FD:
            self[tag] = DataElement.float64s(tag: tag, values: values.map(Float64.init))
        default:
            return false
        }
        return true
    }

    /// Sets a single integer value. See ``setIntegers(_:for:)``.
    @discardableResult
    public mutating func setInteger(_ value: Int, for tag: Tag) -> Bool {
        setIntegers([value], for: tag)
    }

    /// Sets real values, encoding them the way the dictionary's VR requires.
    ///
    /// Graphic Data (0070,0022) is binary `FL` while Window Center (0028,1050)
    /// is a `DS` string; both are written through this one call.
    ///
    /// - Parameters:
    ///   - values: The values to set.
    ///   - tag: The tag to set. Must be a standard tag with a numeric VR.
    ///   - decimalStringFormatter: How to render a value when the VR is `DS`,
    ///     which is length-limited and so needs the caller's own formatting.
    /// - Returns: True when the element was written.
    @discardableResult
    public mutating func setReals(
        _ values: [Double],
        for tag: Tag,
        decimalStringFormatter: (Double) -> String = { Self.defaultDecimalString($0) }
    ) -> Bool {
        guard let vr = Self.dictionaryVR(for: tag) else { return false }
        switch vr {
        case .FL:
            self[tag] = DataElement.float32s(tag: tag, values: values.map(Float32.init))
        case .FD:
            self[tag] = DataElement.float64s(tag: tag, values: values)
        case .DS:
            self[tag] = DataElement.strings(
                tag: tag, vr: .DS, values: values.map(decimalStringFormatter))
        case .IS:
            self[tag] = DataElement.strings(
                tag: tag, vr: .IS, values: values.map { String(Int($0.rounded())) })
        case .US, .SS, .UL, .SL:
            return setIntegers(values.map { Int($0.rounded()) }, for: tag)
        default:
            return false
        }
        return true
    }

    /// Sets a single real value. See ``setReals(_:for:decimalStringFormatter:)``.
    @discardableResult
    public mutating func setReal(
        _ value: Double,
        for tag: Tag,
        decimalStringFormatter: (Double) -> String = { Self.defaultDecimalString($0) }
    ) -> Bool {
        setReals([value], for: tag, decimalStringFormatter: decimalStringFormatter)
    }

    // MARK: - Lookup

    /// The VR the data dictionary gives a tag, or nil when it is not a standard
    /// tag the dictionary knows.
    ///
    /// Where the dictionary lists more than one VR — the `US or SS` of a LUT
    /// descriptor, keyed to Pixel Representation — the first is returned; those
    /// tags are context-dependent and belong in a typed setter, not here.
    public static func dictionaryVR(for tag: Tag) -> VR? {
        guard let entry = DataElementDictionary.lookup(tag: tag),
              let vr = entry.vr.first, vr != .UN else { return nil }
        return vr
    }

    /// A `DS`-safe rendering: at most 16 characters, trailing zeros trimmed.
    public static func defaultDecimalString(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var text = String(format: "%.6f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return String(text.prefix(16))
    }
}

private extension VR {
    /// Whether the VR carries its value as text, so a `String` can be stored
    /// under it directly.
    var isStringRepresentable: Bool {
        switch self {
        case .AE, .AS, .CS, .DA, .DT, .LO, .LT, .PN, .SH, .ST, .TM, .UC, .UI, .UR, .UT,
             .IS, .DS:
            return true
        default:
            return false
        }
    }
}
