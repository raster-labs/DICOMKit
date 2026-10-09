// NEMA-verified: 2026a, checked 2026-09-29 — carries no DICOM-standard data (element container and typed accessors delegating to DICOMCore value types)
import Foundation
import DICOMCore

/// DICOM Data Set
///
/// A collection of data elements, representing either a File Meta Information or main data set.
/// Reference: DICOM PS3.5 Section 7.1 - Data Element Structure
public struct DataSet: Sendable {
    private var elements: [Tag: DataElement]
    
    /// Creates an empty data set
    public init() {
        self.elements = [:]
    }
    
    /// Creates a data set from an array of data elements
    ///
    /// If the array contains duplicate tags the last occurrence wins,
    /// matching PS3.5 §7.1 which requires unique tags but real-world
    /// DICOM files occasionally violate this rule.
    /// - Parameter elements: Array of data elements
    public init(elements: [DataElement]) {
        self.elements = Dictionary(elements.map { ($0.tag, $0) }, uniquingKeysWith: { _, last in last })
    }
    
    /// Accesses a data element by tag
    ///
    /// Use this subscript to get or set data elements in the data set.
    /// Setting a value to nil removes the element.
    public subscript(tag: Tag) -> DataElement? {
        get { elements[tag] }
        set {
            if let newValue = newValue {
                elements[tag] = newValue
            } else {
                elements.removeValue(forKey: tag)
            }
        }
    }
    
    /// Returns the string value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: String value or nil
    public func string(for tag: Tag) -> String? {
        return elements[tag]?.stringValue
    }
    
    /// Returns the string values for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of string values or nil
    public func strings(for tag: Tag) -> [String]? {
        return elements[tag]?.stringValues
    }
    
    /// Returns the UInt16 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: UInt16 value or nil
    public func uint16(for tag: Tag) -> UInt16? {
        return elements[tag]?.uint16Value
    }
    
    /// Returns the UInt32 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: UInt32 value or nil
    public func uint32(for tag: Tag) -> UInt32? {
        return elements[tag]?.uint32Value
    }
    
    /// Returns the UInt16 values array for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of UInt16 values or nil
    public func uint16s(for tag: Tag) -> [UInt16]? {
        return elements[tag]?.uint16Values
    }
    
    /// Returns the UInt32 values array for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of UInt32 values or nil
    public func uint32s(for tag: Tag) -> [UInt32]? {
        return elements[tag]?.uint32Values
    }
    
    /// Returns the Int16 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Int16 value or nil
    public func int16(for tag: Tag) -> Int16? {
        return elements[tag]?.int16Value
    }
    
    /// Returns the Int32 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Int32 value or nil
    public func int32(for tag: Tag) -> Int32? {
        return elements[tag]?.int32Value
    }
    
    /// Returns the Float32 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Float32 value or nil
    public func float32(for tag: Tag) -> Float32? {
        return elements[tag]?.float32Value
    }
    
    /// Returns the Float64 value for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Float64 value or nil
    public func float64(for tag: Tag) -> Float64? {
        return elements[tag]?.float64Value
    }
    
    /// Returns the Float32 values array for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of Float32 values or nil
    public func float32s(for tag: Tag) -> [Float32]? {
        return elements[tag]?.float32Values
    }
    
    /// Returns the Float64 values array for a given tag, if available
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of Float64 values or nil
    public func float64s(for tag: Tag) -> [Float64]? {
        return elements[tag]?.float64Values
    }
    
    // MARK: - Date/Time Value Access
    
    /// Returns the DICOM Date (DA) value for a given tag, if available
    ///
    /// Parses the DICOM Date string (YYYYMMDD format) into a structured DICOMDate.
    /// Reference: PS3.5 Section 6.2 - DA Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMDate or nil
    public func date(for tag: Tag) -> DICOMDate? {
        return elements[tag]?.dateValue
    }
    
    /// Returns the DICOM Time (TM) value for a given tag, if available
    ///
    /// Parses the DICOM Time string (HHMMSS.FFFFFF format) into a structured DICOMTime.
    /// Reference: PS3.5 Section 6.2 - TM Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMTime or nil
    public func time(for tag: Tag) -> DICOMTime? {
        return elements[tag]?.timeValue
    }
    
    /// Returns the DICOM DateTime (DT) value for a given tag, if available
    ///
    /// Parses the DICOM DateTime string into a structured DICOMDateTime.
    /// Reference: PS3.5 Section 6.2 - DT Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMDateTime or nil
    public func dateTime(for tag: Tag) -> DICOMDateTime? {
        return elements[tag]?.dateTimeValue
    }
    
    /// Returns a Foundation Date for a given tag, if available
    ///
    /// Converts DICOM DA or DT values to a Swift Date object.
    /// TM (Time) values alone cannot be converted to a Date.
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Foundation Date or nil
    public func foundationDate(for tag: Tag) -> Date? {
        return elements[tag]?.foundationDateValue
    }
    
    // MARK: - Age String Value Access
    
    /// Returns the DICOM Age String (AS) value for a given tag, if available
    ///
    /// Parses the DICOM Age String (nnnX format) into a structured DICOMAgeString.
    /// Reference: PS3.5 Section 6.2 - AS Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMAgeString or nil
    public func age(for tag: Tag) -> DICOMAgeString? {
        return elements[tag]?.ageValue
    }
    
    // MARK: - Decimal String Value Access
    
    /// Returns the DICOM Decimal String (DS) value for a given tag, if available
    ///
    /// Parses the DICOM Decimal String into a structured DICOMDecimalString.
    /// Reference: PS3.5 Section 6.2 - DS Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMDecimalString or nil
    public func decimalString(for tag: Tag) -> DICOMDecimalString? {
        return elements[tag]?.decimalStringValue
    }
    
    /// Returns multiple DICOM Decimal String (DS) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM Decimal Strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMDecimalString or nil
    public func decimalStrings(for tag: Tag) -> [DICOMDecimalString]? {
        return elements[tag]?.decimalStringValues
    }
    
    // MARK: - Integer String Value Access
    
    /// Returns the DICOM Integer String (IS) value for a given tag, if available
    ///
    /// Parses the DICOM Integer String into a structured DICOMIntegerString.
    /// Reference: PS3.5 Section 6.2 - IS Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMIntegerString or nil
    public func integerString(for tag: Tag) -> DICOMIntegerString? {
        return elements[tag]?.integerStringValue
    }
    
    /// Returns multiple DICOM Integer String (IS) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM Integer Strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMIntegerString or nil
    public func integerStrings(for tag: Tag) -> [DICOMIntegerString]? {
        return elements[tag]?.integerStringValues
    }
    
    // MARK: - Person Name Value Access
    
    /// Returns the DICOM Person Name (PN) value for a given tag, if available
    ///
    /// Parses the DICOM Person Name string into a structured DICOMPersonName.
    /// Reference: PS3.5 Section 6.2 - PN Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMPersonName or nil
    public func personName(for tag: Tag) -> DICOMPersonName? {
        return elements[tag]?.personNameValue
    }
    
    /// Returns multiple DICOM Person Name (PN) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM Person Name strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMPersonName or nil
    public func personNames(for tag: Tag) -> [DICOMPersonName]? {
        return elements[tag]?.personNameValues
    }
    
    // MARK: - Unique Identifier Value Access
    
    /// Returns the DICOM Unique Identifier (UI) value for a given tag, if available
    ///
    /// Parses the DICOM UID string into a structured DICOMUniqueIdentifier.
    /// Reference: PS3.5 Section 6.2 - UI Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMUniqueIdentifier or nil
    public func uid(for tag: Tag) -> DICOMUniqueIdentifier? {
        return elements[tag]?.uidValue
    }
    
    /// Returns multiple DICOM Unique Identifier (UI) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM UID strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMUniqueIdentifier or nil
    public func uids(for tag: Tag) -> [DICOMUniqueIdentifier]? {
        return elements[tag]?.uidValues
    }
    
    // MARK: - Application Entity Value Access
    
    /// Returns the DICOM Application Entity (AE) value for a given tag, if available
    ///
    /// Parses the DICOM AE Title string into a structured DICOMApplicationEntity.
    /// Reference: PS3.5 Section 6.2 - AE Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMApplicationEntity or nil
    public func applicationEntity(for tag: Tag) -> DICOMApplicationEntity? {
        return elements[tag]?.applicationEntityValue
    }
    
    /// Returns multiple DICOM Application Entity (AE) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM AE Title strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMApplicationEntity or nil
    public func applicationEntities(for tag: Tag) -> [DICOMApplicationEntity]? {
        return elements[tag]?.applicationEntityValues
    }
    
    // MARK: - Code String Value Access
    
    /// Returns the DICOM Code String (CS) value for a given tag, if available
    ///
    /// Parses the DICOM Code String into a structured DICOMCodeString.
    /// Reference: PS3.5 Section 6.2 - CS Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMCodeString or nil
    public func codeString(for tag: Tag) -> DICOMCodeString? {
        return elements[tag]?.codeStringValue
    }
    
    /// Returns multiple DICOM Code String (CS) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM Code Strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMCodeString or nil
    public func codeStrings(for tag: Tag) -> [DICOMCodeString]? {
        return elements[tag]?.codeStringValues
    }
    
    // MARK: - Universal Resource Value Access
    
    /// Returns the DICOM Universal Resource (UR) value for a given tag, if available
    ///
    /// Parses the DICOM URI/URL string into a structured DICOMUniversalResource.
    /// Reference: PS3.5 Section 6.2 - UR Value Representation
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: DICOMUniversalResource or nil
    public func universalResource(for tag: Tag) -> DICOMUniversalResource? {
        return elements[tag]?.universalResourceValue
    }
    
    /// Returns multiple DICOM Universal Resource (UR) values for a given tag, if available
    ///
    /// Parses multi-valued DICOM URI/URL strings (backslash-delimited).
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of DICOMUniversalResource or nil
    public func universalResources(for tag: Tag) -> [DICOMUniversalResource]? {
        return elements[tag]?.universalResourceValues
    }
    
    // MARK: - Sequence Element Access
    
    /// Returns the sequence items for a given tag, if available
    ///
    /// Use this method to access sequence data elements (SQ VR).
    /// Returns nil if the element doesn't exist or is not a sequence.
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: Array of sequence items or nil
    public func sequence(for tag: Tag) -> [SequenceItem]? {
        return elements[tag]?.sequenceItems
    }
    
    /// Returns the first item in a sequence for a given tag, if available
    ///
    /// Convenience method for sequences that typically contain only one item.
    ///
    /// - Parameter tag: The tag to retrieve
    /// - Returns: First sequence item or nil
    public func firstSequenceItem(for tag: Tag) -> SequenceItem? {
        return elements[tag]?.sequenceItems?.first
    }
    
    /// Returns the number of items in a sequence for a given tag
    ///
    /// - Parameter tag: The tag to check
    /// - Returns: Number of items, or 0 if not a sequence or doesn't exist
    public func sequenceItemCount(for tag: Tag) -> Int {
        return elements[tag]?.sequenceItemCount ?? 0
    }
    
    /// Checks if the element at the given tag is a sequence
    ///
    /// - Parameter tag: The tag to check
    /// - Returns: True if the element exists and is a sequence (SQ VR)
    public func isSequence(tag: Tag) -> Bool {
        return elements[tag]?.isSequence ?? false
    }
    
    /// Number of elements in the data set
    public var count: Int {
        return elements.count
    }
    
    /// All tags in the data set
    public var tags: [Tag] {
        return Array(elements.keys).sorted()
    }
    
    /// All data elements in tag order
    public var allElements: [DataElement] {
        let sortedTags = tags
        return sortedTags.compactMap { elements[$0] }
    }
}

// MARK: - Sequence Conformance
extension DataSet: Sequence {
    public func makeIterator() -> IndexingIterator<[DataElement]> {
        return allElements.makeIterator()
    }
}
