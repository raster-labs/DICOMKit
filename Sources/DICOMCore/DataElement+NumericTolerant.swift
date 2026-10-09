//
// DataElement+NumericTolerant.swift
// DICOMCore
//
// NEMA-verified: 2026a, checked 2026-09-25 — carries no DICOM-standard data (VR names only, all in PS3.5 2026a Table 6.2-1). C1 classification confirmed.

import Foundation

// MARK: - VR-Tolerant Numeric Reading

extension DataElement {

    /// Reads the element's values as integers regardless of how they are encoded.
    ///
    /// Numeric attributes in the presentation-state modules are binary (`US`,
    /// `SS`, `SL`, `UL`), but the same numbers are also legal — and were once
    /// written by this library — as `IS` text. Reading through this accessor
    /// keeps both forms parseable, so an object written before the VRs were
    /// corrected still restores its zoom, pan, and layer colours.
    ///
    /// - Returns: The values, or nil if the element carries no readable number.
    public var integerValuesTolerant: [Int]? {
        switch vr {
        case .US:
            return uint16Values?.map(Int.init)
        case .SS:
            return int16Values?.map(Int.init)
        case .UL:
            return uint32Values?.map(Int.init)
        case .SL:
            return int32Values?.map(Int.init)
        case .IS:
            return integerStringValues?.map { Int($0.value) }
        case .DS:
            // A whole number written as a decimal string still reads as one.
            return decimalStringValues?.map { Int($0.value.rounded()) }
        case .FL:
            return float32Values?.map { Int($0.rounded()) }
        case .FD:
            return float64Values?.map { Int($0.rounded()) }
        default:
            return nil
        }
    }

    /// The single integer value, regardless of encoding. See ``integerValuesTolerant``.
    public var integerValueTolerant: Int? {
        integerValuesTolerant?.first
    }

    /// Reads the element's values as reals regardless of how they are encoded.
    ///
    /// The counterpart to ``integerValuesTolerant`` for the coordinate-valued
    /// attributes, which are `FL` per the dictionary but were previously
    /// written by this library as `DS` text.
    ///
    /// - Returns: The values, or nil if the element carries no readable number.
    public var realValuesTolerant: [Double]? {
        switch vr {
        case .FL:
            return float32Values?.map(Double.init)
        case .FD:
            return float64Values
        case .DS:
            return decimalStringValues?.map(\.value)
        case .IS:
            return integerStringValues?.map { Double($0.value) }
        case .US:
            return uint16Values?.map(Double.init)
        case .SS:
            return int16Values?.map(Double.init)
        case .UL:
            return uint32Values?.map(Double.init)
        case .SL:
            return int32Values?.map(Double.init)
        default:
            return nil
        }
    }

    /// The single real value, regardless of encoding. See ``realValuesTolerant``.
    public var realValueTolerant: Double? {
        realValuesTolerant?.first
    }
}
