import Foundation

/// DICOM Data Element
///
/// A data element is a unit of information as defined by a single entry in the data dictionary.
/// It consists of a tag, VR, length, and value field.
///
/// Reference: DICOM PS3.5 Section 7.1 - Data Element Structure
/// NEMA-verified: 2026a, checked 2026-09-25 — the 64-bit accessors (uint64/int64, OV/SV/UV) added under P1 on 2026-09-24 follow PS3.5 2026a Table 6.2-1 (CP 1819, 2019a) and the byte-order rule of §7.3; string/numeric accessors follow the VR definitions of Table 6.2-1. Re-checked for this marker on 2026-09-25; `stringValues` keeps empty values of a multi-valued attribute per §6.4 (D25, 2026-09-28).
public struct DataElement: Sendable {
    /// Data element tag (group, element pair)
    public let tag: Tag
    
    /// Value Representation
    public let vr: VR
    
    /// Value length in bytes
    ///
    /// The value 0xFFFFFFFF (4294967295) indicates an undefined length.
    /// Reference: PS3.5 Section 7.1.2
    public let length: UInt32
    
    /// Raw value data
    public let valueData: Data

    /// Byte order the raw `valueData` is encoded in, used by the numeric value accessors.
    ///
    /// Almost always `.littleEndian`. It is `.bigEndian` only for elements parsed from a
    /// dataset that uses the retired **Explicit VR Big Endian** transfer syntax
    /// (1.2.840.10008.1.2.2), so multi-byte numeric values (US/UL/SS/SL/FL/FD, …) decode in
    /// the correct order rather than silently byte-swapping. Defaults to `.littleEndian` for
    /// source compatibility with all existing constructors.
    /// Reference: PS3.5 §7.1.1 / §7.1.2.
    public let byteOrder: ByteOrder

    /// Sequence items for SQ (Sequence) VR elements
    ///
    /// Contains the parsed sequence items when this element has VR of SQ.
    /// Each item in the array represents a single sequence item containing
    /// nested data elements.
    ///
    /// Reference: PS3.5 Section 7.5 - Nesting of Data Sets
    public let sequenceItems: [SequenceItem]?
    
    /// Encapsulated pixel data fragments for compressed pixel data
    ///
    /// When pixel data is encapsulated (compressed), the data is stored
    /// as a sequence of fragments. Each fragment is a separate Data block.
    ///
    /// Reference: PS3.5 Section A.4 - Transfer Syntaxes For Encapsulation
    public let encapsulatedFragments: [Data]?
    
    /// Basic Offset Table for encapsulated pixel data
    ///
    /// Contains byte offsets to each frame in the encapsulated pixel data.
    /// May be empty if the encoder did not provide offset information.
    ///
    /// Reference: PS3.5 Section A.4 - Table A.4-1
    public let encapsulatedOffsetTable: [UInt32]?
    
    /// Creates a new data element
    /// - Parameters:
    ///   - tag: Data element tag
    ///   - vr: Value Representation
    ///   - length: Value length (use 0xFFFFFFFF for undefined length)
    ///   - valueData: Raw value data
    public init(tag: Tag, vr: VR, length: UInt32, valueData: Data, byteOrder: ByteOrder = .littleEndian) {
        self.tag = tag
        self.vr = vr
        self.length = length
        self.valueData = valueData
        self.byteOrder = byteOrder
        self.sequenceItems = nil
        self.encapsulatedFragments = nil
        self.encapsulatedOffsetTable = nil
    }
    
    /// Creates a new sequence data element
    /// - Parameters:
    ///   - tag: Data element tag
    ///   - vr: Value Representation (should be .SQ)
    ///   - length: Value length (use 0xFFFFFFFF for undefined length)
    ///   - valueData: Raw value data
    ///   - sequenceItems: Parsed sequence items
    public init(tag: Tag, vr: VR, length: UInt32, valueData: Data, sequenceItems: [SequenceItem], byteOrder: ByteOrder = .littleEndian) {
        self.tag = tag
        self.vr = vr
        self.length = length
        self.valueData = valueData
        self.byteOrder = byteOrder
        self.sequenceItems = sequenceItems
        self.encapsulatedFragments = nil
        self.encapsulatedOffsetTable = nil
    }
    
    /// Creates a new encapsulated pixel data element
    /// - Parameters:
    ///   - tag: Data element tag
    ///   - vr: Value Representation (should be .OB or .OW)
    ///   - length: Value length (typically 0xFFFFFFFF for undefined length)
    ///   - valueData: Raw value data (typically empty for encapsulated)
    ///   - encapsulatedFragments: Compressed pixel data fragments
    ///   - encapsulatedOffsetTable: Basic offset table
    public init(tag: Tag, vr: VR, length: UInt32, valueData: Data, encapsulatedFragments: [Data], encapsulatedOffsetTable: [UInt32], byteOrder: ByteOrder = .littleEndian) {
        self.tag = tag
        self.vr = vr
        self.length = length
        self.valueData = valueData
        self.byteOrder = byteOrder
        self.sequenceItems = nil
        self.encapsulatedFragments = encapsulatedFragments
        self.encapsulatedOffsetTable = encapsulatedOffsetTable
    }
    
    /// Indicates whether this data element has undefined length
    ///
    /// Reference: PS3.5 Section 7.1.2 - Data Element with Explicit Length
    public var hasUndefinedLength: Bool {
        return length == 0xFFFFFFFF
    }
    
    /// Indicates whether this data element is a sequence (SQ VR)
    ///
    /// Reference: PS3.5 Section 7.5 - Nesting of Data Sets
    public var isSequence: Bool {
        return vr == .SQ
    }
    
    /// Indicates whether this data element contains encapsulated pixel data
    ///
    /// Reference: PS3.5 Section A.4 - Transfer Syntaxes For Encapsulation
    public var isEncapsulated: Bool {
        return encapsulatedFragments != nil && !(encapsulatedFragments?.isEmpty ?? true)
    }
    
    /// Number of items in the sequence
    ///
    /// Returns 0 if this element is not a sequence or has no items.
    public var sequenceItemCount: Int {
        return sequenceItems?.count ?? 0
    }
    
    /// Number of fragments in encapsulated pixel data
    ///
    /// Returns 0 if this element does not contain encapsulated data.
    public var encapsulatedFragmentCount: Int {
        return encapsulatedFragments?.count ?? 0
    }
    
    /// Extracts the value as a string (for string-based VRs)
    ///
    /// Returns nil if the VR doesn't support string values or if decoding fails.
    /// Trims leading/trailing whitespace and null padding per DICOM conventions.
    ///
    /// Reference: PS3.5 Section 6.2 - Value padding uses space (0x20) for most
    /// string VRs and null (0x00) for UI.
    public var stringValue: String? {
        guard vr.characterRepertoire != nil else {
            return nil
        }
        
        guard let string = String(data: valueData, encoding: .utf8) else {
            return nil
        }
        
        // Create a character set containing whitespace, newlines, and null characters
        // DICOM pads UI with null (0x00) and other string VRs with space (0x20)
        var trimmingSet = CharacterSet.whitespacesAndNewlines
        trimmingSet.insert(charactersIn: "\0")
        
        return string.trimmingCharacters(in: trimmingSet)
    }
    
    /// Extracts multiple string values (for multi-valued string VRs)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values. An empty value between
    /// two delimiters is a value (PS3.5 Section 6.4: "MPG\\XR3" has a Value Multiplicity of
    /// three, the second value zero length), so empty values are kept in their position; a
    /// zero-length or padding-only Value Field has no values.
    /// Reference: PS3.5 Section 6.2, Section 6.4
    public var stringValues: [String]? {
        guard let value = stringValue else {
            return nil
        }
        guard !value.isEmpty else {
            return []
        }
        return value.components(separatedBy: "\\").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    /// Extracts the value as a 16-bit unsigned integer
    ///
    /// Supports VR types that can contain 16-bit values:
    /// - US (Unsigned Short): Primary VR for unsigned 16-bit values
    /// - SS (Signed Short): Binary compatible, reads raw 2-byte value
    /// - UN (Unknown): Unknown VR with 2-byte data
    /// - OW (Other Word): 16-bit words
    /// - OB (Other Byte): When exactly 2 bytes, can represent a 16-bit value
    /// - IS (Integer String): Some non-compliant DICOM files use IS for pixel attributes
    ///
    /// **Note**: For SS VR, the raw bytes are read directly. If the signed value
    /// is negative, it will appear as a large unsigned value (e.g., -1 → 65535).
    /// For DICOM image pixel attributes like Rows, Columns, Bits Allocated, etc.,
    /// values are always non-negative, so this behavior is correct.
    ///
    /// This flexibility is needed because some valid DICOM files may encode
    /// pixel descriptor attributes with different VRs than strictly specified.
    /// Some DICOM implementations incorrectly encode US attributes as OB or IS.
    /// Reference: PS3.5 Section 6.2
    // MARK: - Byte-order-aware numeric readers
    //
    // Decode multi-byte numeric values honoring `byteOrder`, so an element parsed from an
    // Explicit VR Big Endian dataset (1.2.840.10008.1.2.2) yields correct values instead of
    // byte-swapped ones. Little-endian is the default/fast path.

    private func readUInt16(at offset: Int) -> UInt16? {
        byteOrder == .bigEndian ? valueData.readUInt16BE(at: offset) : valueData.readUInt16LE(at: offset)
    }
    private func readUInt32(at offset: Int) -> UInt32? {
        byteOrder == .bigEndian ? valueData.readUInt32BE(at: offset) : valueData.readUInt32LE(at: offset)
    }
    private func readInt16(at offset: Int) -> Int16? {
        byteOrder == .bigEndian ? valueData.readInt16BE(at: offset) : valueData.readInt16LE(at: offset)
    }
    private func readInt32(at offset: Int) -> Int32? {
        byteOrder == .bigEndian ? valueData.readInt32BE(at: offset) : valueData.readInt32LE(at: offset)
    }
    private func readFloat32(at offset: Int) -> Float32? {
        byteOrder == .bigEndian ? valueData.readFloat32BE(at: offset) : valueData.readFloat32LE(at: offset)
    }
    private func readFloat64(at offset: Int) -> Float64? {
        byteOrder == .bigEndian ? valueData.readFloat64BE(at: offset) : valueData.readFloat64LE(at: offset)
    }
    private func readUInt64(at offset: Int) -> UInt64? {
        byteOrder == .bigEndian ? valueData.readUInt64BE(at: offset) : valueData.readUInt64LE(at: offset)
    }
    private func readInt64(at offset: Int) -> Int64? {
        readUInt64(at: offset).map { Int64(bitPattern: $0) }
    }

    /// Extracts the value as a single Attribute Tag (AT VR).
    ///
    /// An AT value is two consecutive 16-bit unsigned integers: group then element,
    /// each in this element's byte order. Returns nil for non-AT VRs or when the
    /// value is shorter than four bytes.
    ///
    /// Reference: PS3.5 Section 6.2, Table 6.2-1
    public var attributeTagValue: Tag? {
        return attributeTagValues?.first
    }

    /// Extracts all Attribute Tag (AT VR) values.
    ///
    /// Reference: PS3.5 Section 6.2, Table 6.2-1
    public var attributeTagValues: [Tag]? {
        guard vr == .AT else { return nil }
        guard valueData.count >= 4 else { return nil }
        var tags: [Tag] = []
        var offset = 0
        while offset + 4 <= valueData.count {
            guard let group = readUInt16(at: offset),
                  let element = readUInt16(at: offset + 2) else {
                return tags.isEmpty ? nil : tags
            }
            tags.append(Tag(group: group, element: element))
            offset += 4
        }
        return tags.isEmpty ? nil : tags
    }

    public var uint16Value: UInt16? {
        // Accept VRs that can contain 16-bit integer data
        switch vr {
        case .US, .SS, .UN, .OW:
            guard valueData.count >= 2 else {
                return nil
            }
            return readUInt16(at: 0)
        case .OB:
            // Support OB with exactly 2 bytes as some DICOM files incorrectly use OB for US values
            guard valueData.count == 2 else {
                return nil
            }
            return readUInt16(at: 0)
        case .IS:
            // Support IS (Integer String) for non-compliant DICOM files that encode
            // pixel attributes like Rows, Columns, Bits Allocated, etc. as IS instead of US
            return integerStringValue?.uint16Value
        default:
            return nil
        }
    }
    
    /// Extracts the value as a 32-bit unsigned integer
    ///
    /// Supports VR types that can contain 32-bit values:
    /// - UL (Unsigned Long): Primary VR for unsigned 32-bit values
    /// - SL (Signed Long): Binary compatible, reads raw 4-byte value
    /// - UN (Unknown): Unknown VR with 4-byte data
    /// - OL (Other Long): 32-bit words
    ///
    /// **Note**: For SL VR, the raw bytes are read directly. If the signed value
    /// is negative, it will appear as a large unsigned value. For DICOM length
    /// fields and similar attributes, values are always non-negative.
    ///
    /// Reference: PS3.5 Section 6.2
    public var uint32Value: UInt32? {
        // Accept VRs that can contain 32-bit integer data
        switch vr {
        case .UL, .SL, .UN, .OL:
            guard valueData.count >= 4 else {
                return nil
            }
            return readUInt32(at: 0)
        default:
            return nil
        }
    }
    
    /// Extracts the value as a 16-bit signed integer (for SS VR)
    public var int16Value: Int16? {
        guard vr == .SS && valueData.count >= 2 else {
            return nil
        }
        return readInt16(at: 0)
    }
    
    /// Extracts the value as a 32-bit signed integer (for SL VR)
    public var int32Value: Int32? {
        guard vr == .SL && valueData.count >= 4 else {
            return nil
        }
        return readInt32(at: 0)
    }
    
    /// Extracts the value as a 32-bit floating point (for FL VR)
    public var float32Value: Float32? {
        guard vr == .FL && valueData.count >= 4 else {
            return nil
        }
        return readFloat32(at: 0)
    }
    
    /// Extracts the value as a 64-bit floating point (for FD VR)
    public var float64Value: Float64? {
        guard vr == .FD && valueData.count >= 8 else {
            return nil
        }
        return readFloat64(at: 0)
    }

    /// Extracts the value as a 64-bit unsigned integer
    ///
    /// Supports VR types that can contain 64-bit values:
    /// - UV (Unsigned 64-bit Very Long): Primary VR for unsigned 64-bit values
    /// - SV (Signed 64-bit Very Long): Binary compatible, reads raw 8-byte value
    /// - UN (Unknown): Unknown VR with 8-byte data
    /// - OV (Other 64-bit Very Long): 64-bit words
    ///
    /// **Note**: For SV VR, the raw bytes are read directly. If the signed value
    /// is negative, it will appear as a large unsigned value.
    ///
    /// Reference: PS3.5 Section 6.2 (CP 1819)
    public var uint64Value: UInt64? {
        switch vr {
        case .UV, .SV, .UN, .OV:
            guard valueData.count >= 8 else {
                return nil
            }
            return readUInt64(at: 0)
        default:
            return nil
        }
    }

    /// Extracts the value as a 64-bit signed integer (for SV VR)
    public var int64Value: Int64? {
        guard vr == .SV && valueData.count >= 8 else {
            return nil
        }
        return readInt64(at: 0)
    }
    
    /// Extracts multiple 16-bit unsigned integer values
    ///
    /// Supports VR types that can contain 16-bit values:
    /// - US (Unsigned Short): Primary VR for unsigned 16-bit values
    /// - SS (Signed Short): Signed 16-bit, interpreted as unsigned
    /// - UN (Unknown): Unknown VR with 2-byte data
    /// - OW (Other Word): 16-bit words
    /// - OB (Other Byte): When data length is a multiple of 2 bytes
    ///
    /// Many DICOM elements can have multiple values. This property returns all values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var uint16Values: [UInt16]? {
        // Accept VRs that can contain 16-bit integer data
        switch vr {
        case .US, .SS, .UN, .OW:
            break
        case .OB:
            // Support OB when data length is even (can be interpreted as 16-bit values)
            guard valueData.count % 2 == 0 else {
                return nil
            }
        default:
            return nil
        }
        
        let count = valueData.count / 2
        guard count > 0 else {
            return []
        }
        
        var values: [UInt16] = []
        for i in 0..<count {
            if let value = readUInt16(at: i * 2) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 32-bit unsigned integer values
    ///
    /// Supports VR types that can contain 32-bit values:
    /// - UL (Unsigned Long): Primary VR for unsigned 32-bit values
    /// - SL (Signed Long): Signed 32-bit, interpreted as unsigned
    /// - UN (Unknown): Unknown VR with 4-byte data
    /// - OL (Other Long): 32-bit words
    ///
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var uint32Values: [UInt32]? {
        // Accept VRs that can contain 32-bit integer data
        switch vr {
        case .UL, .SL, .UN, .OL:
            break
        default:
            return nil
        }
        
        let count = valueData.count / 4
        guard count > 0 else {
            return []
        }
        
        var values: [UInt32] = []
        for i in 0..<count {
            if let value = readUInt32(at: i * 4) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 16-bit signed integer values (for SS VR with multiplicity)
    public var int16Values: [Int16]? {
        guard vr == .SS else {
            return nil
        }
        
        let count = valueData.count / 2
        guard count > 0 else {
            return []
        }
        
        var values: [Int16] = []
        for i in 0..<count {
            if let value = readInt16(at: i * 2) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 32-bit signed integer values (for SL VR with multiplicity)
    public var int32Values: [Int32]? {
        guard vr == .SL else {
            return nil
        }
        
        let count = valueData.count / 4
        guard count > 0 else {
            return []
        }
        
        var values: [Int32] = []
        for i in 0..<count {
            if let value = readInt32(at: i * 4) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 32-bit floating point values (for FL VR with multiplicity)
    public var float32Values: [Float32]? {
        guard vr == .FL else {
            return nil
        }
        
        let count = valueData.count / 4
        guard count > 0 else {
            return []
        }
        
        var values: [Float32] = []
        for i in 0..<count {
            if let value = readFloat32(at: i * 4) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 64-bit floating point values (for FD VR with multiplicity)
    public var float64Values: [Float64]? {
        guard vr == .FD else {
            return nil
        }
        
        let count = valueData.count / 8
        guard count > 0 else {
            return []
        }
        
        var values: [Float64] = []
        for i in 0..<count {
            if let value = readFloat64(at: i * 8) {
                values.append(value)
            }
        }
        
        return values.isEmpty ? nil : values
    }
    
    /// Extracts multiple 64-bit unsigned integer values
    ///
    /// Supports VR types that can contain 64-bit values:
    /// - UV (Unsigned 64-bit Very Long): Primary VR for unsigned 64-bit values
    /// - SV (Signed 64-bit Very Long): Signed 64-bit, interpreted as unsigned
    /// - UN (Unknown): Unknown VR with 8-byte data
    /// - OV (Other 64-bit Very Long): 64-bit words, e.g. Extended Offset Table (7FE0,0001)
    ///
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity (CP 1819)
    public var uint64Values: [UInt64]? {
        switch vr {
        case .UV, .SV, .UN, .OV:
            break
        default:
            return nil
        }

        let count = valueData.count / 8
        guard count > 0 else {
            return []
        }

        var values: [UInt64] = []
        for i in 0..<count {
            if let value = readUInt64(at: i * 8) {
                values.append(value)
            }
        }

        return values.isEmpty ? nil : values
    }

    /// Extracts multiple 64-bit signed integer values (for SV VR with multiplicity)
    public var int64Values: [Int64]? {
        guard vr == .SV else {
            return nil
        }

        let count = valueData.count / 8
        guard count > 0 else {
            return []
        }

        var values: [Int64] = []
        for i in 0..<count {
            if let value = readInt64(at: i * 8) {
                values.append(value)
            }
        }

        return values.isEmpty ? nil : values
    }

    // MARK: - Date/Time Value Extraction
    
    /// Extracts the value as a DICOM Date (for DA VR)
    ///
    /// Parses the DICOM Date string (YYYYMMDD format) into a structured DICOMDate.
    /// Reference: PS3.5 Section 6.2 - DA Value Representation
    public var dateValue: DICOMDate? {
        guard vr == .DA, let string = stringValue else {
            return nil
        }
        return DICOMDate.parse(string)
    }
    
    /// Extracts the value as a DICOM Time (for TM VR)
    ///
    /// Parses the DICOM Time string (HHMMSS.FFFFFF format) into a structured DICOMTime.
    /// Reference: PS3.5 Section 6.2 - TM Value Representation
    public var timeValue: DICOMTime? {
        guard vr == .TM, let string = stringValue else {
            return nil
        }
        return DICOMTime.parse(string)
    }
    
    /// Extracts the value as a DICOM DateTime (for DT VR)
    ///
    /// Parses the DICOM DateTime string into a structured DICOMDateTime.
    /// Reference: PS3.5 Section 6.2 - DT Value Representation
    public var dateTimeValue: DICOMDateTime? {
        guard vr == .DT, let string = stringValue else {
            return nil
        }
        return DICOMDateTime.parse(string)
    }
    
    /// Extracts the value as a Foundation Date (for DA, TM, or DT VR)
    ///
    /// Converts DICOM date/time values to a Swift Date object.
    /// - For DA (Date): Returns date at midnight UTC
    /// - For TM (Time): Returns nil (time alone cannot be converted to Date)
    /// - For DT (DateTime): Returns full date and time
    ///
    /// Reference: PS3.5 Section 6.2
    public var foundationDateValue: Date? {
        switch vr {
        case .DA:
            return dateValue?.toDate()
        case .DT:
            return dateTimeValue?.toDate()
        default:
            return nil
        }
    }
    
    // MARK: - Age String Value Extraction
    
    /// Extracts the value as a DICOM Age String (for AS VR)
    ///
    /// Parses the DICOM Age String (nnnX format) into a structured DICOMAgeString.
    /// Reference: PS3.5 Section 6.2 - AS Value Representation
    public var ageValue: DICOMAgeString? {
        guard vr == .AS, let string = stringValue else {
            return nil
        }
        return DICOMAgeString.parse(string)
    }
    
    // MARK: - Decimal String Value Extraction
    
    /// Extracts the value as a DICOM Decimal String (for DS VR)
    ///
    /// Parses the DICOM Decimal String into a structured DICOMDecimalString.
    /// Reference: PS3.5 Section 6.2 - DS Value Representation
    public var decimalStringValue: DICOMDecimalString? {
        guard vr == .DS, let string = stringValue else {
            return nil
        }
        return DICOMDecimalString.parse(string)
    }
    
    /// Extracts multiple DICOM Decimal String values (for DS VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var decimalStringValues: [DICOMDecimalString]? {
        guard vr == .DS, let string = stringValue else {
            return nil
        }
        return DICOMDecimalString.parseMultiple(string)
    }
    
    // MARK: - Integer String Value Extraction
    
    /// Extracts the value as a DICOM Integer String (for IS VR)
    ///
    /// Parses the DICOM Integer String into a structured DICOMIntegerString.
    /// Reference: PS3.5 Section 6.2 - IS Value Representation
    public var integerStringValue: DICOMIntegerString? {
        guard vr == .IS, let string = stringValue else {
            return nil
        }
        return DICOMIntegerString.parse(string)
    }
    
    /// Extracts multiple DICOM Integer String values (for IS VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var integerStringValues: [DICOMIntegerString]? {
        guard vr == .IS, let string = stringValue else {
            return nil
        }
        return DICOMIntegerString.parseMultiple(string)
    }
    
    // MARK: - Person Name Value Extraction
    
    /// Extracts the value as a DICOM Person Name (for PN VR)
    ///
    /// Parses the DICOM Person Name string into a structured DICOMPersonName.
    /// Reference: PS3.5 Section 6.2 - PN Value Representation
    public var personNameValue: DICOMPersonName? {
        guard vr == .PN, let string = stringValue else {
            return nil
        }
        return DICOMPersonName.parse(string)
    }
    
    /// Extracts multiple DICOM Person Name values (for PN VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var personNameValues: [DICOMPersonName]? {
        guard vr == .PN, let strings = stringValues else {
            return nil
        }
        let names = strings.compactMap { DICOMPersonName.parse($0) }
        return names.isEmpty ? nil : names
    }
    
    // MARK: - Unique Identifier Value Extraction
    
    /// Extracts the value as a DICOM Unique Identifier (for UI VR)
    ///
    /// Parses the DICOM UID string into a structured DICOMUniqueIdentifier.
    /// Reference: PS3.5 Section 6.2 - UI Value Representation
    public var uidValue: DICOMUniqueIdentifier? {
        guard vr == .UI, let string = stringValue else {
            return nil
        }
        return DICOMUniqueIdentifier.parse(string)
    }
    
    /// Extracts multiple DICOM Unique Identifier values (for UI VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var uidValues: [DICOMUniqueIdentifier]? {
        guard vr == .UI, let string = stringValue else {
            return nil
        }
        return DICOMUniqueIdentifier.parseMultiple(string)
    }
    
    // MARK: - Application Entity Value Extraction
    
    /// Extracts the value as a DICOM Application Entity (for AE VR)
    ///
    /// Parses the DICOM AE Title string into a structured DICOMApplicationEntity.
    /// Reference: PS3.5 Section 6.2 - AE Value Representation
    public var applicationEntityValue: DICOMApplicationEntity? {
        guard vr == .AE, let string = stringValue else {
            return nil
        }
        return DICOMApplicationEntity.parse(string)
    }
    
    /// Extracts multiple DICOM Application Entity values (for AE VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var applicationEntityValues: [DICOMApplicationEntity]? {
        guard vr == .AE, let string = stringValue else {
            return nil
        }
        return DICOMApplicationEntity.parseMultiple(string)
    }
    
    // MARK: - Code String Value Extraction
    
    /// Extracts the value as a DICOM Code String (for CS VR)
    ///
    /// Parses the DICOM Code String into a structured DICOMCodeString.
    /// Reference: PS3.5 Section 6.2 - CS Value Representation
    public var codeStringValue: DICOMCodeString? {
        guard vr == .CS, let string = stringValue else {
            return nil
        }
        return DICOMCodeString.parse(string)
    }
    
    /// Extracts multiple DICOM Code String values (for CS VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var codeStringValues: [DICOMCodeString]? {
        guard vr == .CS, let string = stringValue else {
            return nil
        }
        return DICOMCodeString.parseMultiple(string)
    }
    
    // MARK: - Universal Resource Value Extraction
    
    /// Extracts the value as a DICOM Universal Resource (for UR VR)
    ///
    /// Parses the DICOM URI/URL string into a structured DICOMUniversalResource.
    /// Reference: PS3.5 Section 6.2 - UR Value Representation
    public var universalResourceValue: DICOMUniversalResource? {
        guard vr == .UR, let string = stringValue else {
            return nil
        }
        return DICOMUniversalResource.parse(string)
    }
    
    /// Extracts multiple DICOM Universal Resource values (for UR VR with multiplicity)
    ///
    /// DICOM uses backslash (\) as a delimiter for multiple values.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    public var universalResourceValues: [DICOMUniversalResource]? {
        guard vr == .UR, let string = stringValue else {
            return nil
        }
        return DICOMUniversalResource.parseMultiple(string)
    }
}
