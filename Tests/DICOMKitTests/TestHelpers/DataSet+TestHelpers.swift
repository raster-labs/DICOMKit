//
// DataSet+TestHelpers.swift
// DICOMKit
//
// Created by DICOMKit on 2026-02-06.
// Copyright © 2026 DICOMKit. All rights reserved.
//

import Foundation
import DICOMCore
import DICOMDictionary
@testable import DICOMKit

/// Test helper extension for DataSet to simplify test data creation
extension DataSet {
    /// Convenience method to append string values to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The string value
    mutating func append(_ tag: Tag, _ value: String) {
        // Determine VR based on tag
        let vr: VR
        if let entry = DataElementDictionary.lookup(tag: tag), let firstVR = entry.vr.first {
            vr = firstVR
        } else {
            // Default to LO for unknown tags
            vr = .LO
        }
        self[tag] = DataElement.string(tag: tag, vr: vr, value: value)
    }
    
    /// Convenience method to append UInt16 values to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The UInt16 value
    mutating func append(_ tag: Tag, _ value: UInt16) {
        self[tag] = DataElement.uint16(tag: tag, value: value)
    }
    
    /// Convenience method to append Int values to a DataSet
    ///
    /// The element takes the dictionary VR of `tag` (IS as a string, US/SS/UL/SL
    /// as binary), so the parsers under test see the same encoding a real file
    /// carries. An unknown tag falls back to SL.
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The Int value
    mutating func append(_ tag: Tag, _ value: Int) {
        switch DataElementDictionary.lookup(tag: tag)?.vr.first {
        case .IS?, .DS?, .LO?, .SH?, .CS?, .ST?, .LT?, .UT?:
            self[tag] = DataElement.string(tag: tag, vr: DataElementDictionary.lookup(tag: tag)!.vr.first!, value: String(value))
        case .US?:
            self[tag] = DataElement.uint16(tag: tag, value: UInt16(clamping: value))
        case .SS?:
            self[tag] = DataElement.int16(tag: tag, value: Int16(clamping: value))
        case .UL?:
            self[tag] = DataElement.uint32(tag: tag, value: UInt32(clamping: value))
        case .FD?:
            self[tag] = DataElement.float64(tag: tag, value: Double(value))
        case .FL?:
            self[tag] = DataElement.float32(tag: tag, value: Float(value))
        default:
            self[tag] = DataElement.int32(tag: tag, value: Int32(clamping: value))
        }
    }
    
    /// Convenience method to append array of Int values to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - values: Array of Int values
    mutating func append(_ tag: Tag, _ values: [Int]) {
        // Convert to Int32 array for DICOM
        let int32Values = values.map { Int32($0) }
        // Determine VR - for frame numbers and similar, use IS (Integer String)
        let vr: VR
        if let entry = DataElementDictionary.lookup(tag: tag), let firstVR = entry.vr.first {
            vr = firstVR
        } else {
            vr = .IS
        }
        // Use string representation for IS VR
        if vr == .IS {
            let stringValues = int32Values.map { String($0) }
            let combinedString = stringValues.joined(separator: "\\")
            self[tag] = DataElement.string(tag: tag, vr: .IS, value: combinedString)
        } else {
            // Use int32 array for SL VR
            let writer = DICOMWriter()
            let data = writer.serializeInt32s(int32Values)
            self[tag] = DataElement(tag: tag, vr: .SL, length: UInt32(data.count), valueData: data)
        }
    }
    
    /// Convenience method to append Double values to a DataSet
    ///
    /// DS tags are written as decimal strings, FL as Float32; anything else
    /// (FD, unknown) as Float64.
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The Double value
    mutating func append(_ tag: Tag, _ value: Double) {
        switch DataElementDictionary.lookup(tag: tag)?.vr.first {
        case .DS?:
            self[tag] = DataElement.string(tag: tag, vr: .DS, value: String(value))
        case .FL?:
            self[tag] = DataElement.float32(tag: tag, value: Float(value))
        default:
            self[tag] = DataElement.float64(tag: tag, value: value)
        }
    }
    
    /// Convenience method to append DICOMDate values to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The DICOMDate value
    mutating func append(_ tag: Tag, _ value: DICOMDate) {
        self[tag] = DataElement.string(tag: tag, vr: .DA, value: value.dicomString)
    }
    
    /// Convenience method to append DICOMTime values to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - value: The DICOMTime value
    mutating func append(_ tag: Tag, _ value: DICOMTime) {
        self[tag] = DataElement.string(tag: tag, vr: .TM, value: value.dicomString)
    }
    
    /// Convenience method to append sequence items to a DataSet
    /// - Parameters:
    ///   - tag: The tag to append
    ///   - items: Array of DataSet items to append as a sequence
    mutating func appendSequence(_ tag: Tag, _ items: [DataSet]) {
        let sequenceItems = items.map { dataSet in
            SequenceItem(elements: dataSet.allElements)
        }
        let valueData = Data() // Empty for sequences
        self[tag] = DataElement(tag: tag, vr: .SQ, length: 0xFFFFFFFF, valueData: valueData, sequenceItems: sequenceItems)
    }
}
