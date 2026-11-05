import Foundation

/// DICOM Data Writer
///
/// Serializes DICOM data elements to binary format according to DICOM PS3.5.
/// Supports Explicit VR Little Endian transfer syntax (the most common format).
///
/// Reference: DICOM PS3.5 Section 7.1 - Data Element Encoding Rules
///
/// NEMA-verified: 2026a, checked 2026-10-01 — values are written in the writer's byte order, swapping 2-byte US/SS/OW/AT, 4-byte UL/SL/FL/OF/OL and 8-byte FD/OD/OV/SV/UV units when the element's order differs (PS3.5 2026a 7.3; D206); element headers (Tables 7.1-1/7.1-2 with the 13 32-bit-length VRs), padding (SPACE for strings, NULL for UI and OB, PS3.5 Table 6.2-1), backslash value separators, explicit-length Items (§7.5.1) and encapsulated Pixel Data layout (§A.4: undefined length, Basic Offset Table Item, even-length fragment Items, Sequence Delimitation Item) all match PS3.5 2026a.
public struct DICOMWriter: Sendable {
    
    /// The byte order for writing multi-byte values
    public let byteOrder: ByteOrder
    
    /// Whether to use Explicit VR encoding
    public let explicitVR: Bool
    
    /// Creates a DICOM writer with specified encoding parameters
    /// - Parameters:
    ///   - byteOrder: Byte order for multi-byte values (default: Little Endian)
    ///   - explicitVR: Whether to use Explicit VR encoding (default: true)
    public init(byteOrder: ByteOrder = .littleEndian, explicitVR: Bool = true) {
        self.byteOrder = byteOrder
        self.explicitVR = explicitVR
    }
    
    // MARK: - Value Serialization
    
    /// Pads a string value to an even length as required by DICOM
    ///
    /// DICOM requires all values to have even byte lengths.
    /// String VRs are padded with space (0x20) for most VRs or null (0x00) for UI.
    ///
    /// Reference: PS3.5 Section 6.2 - Padding
    ///
    /// - Parameters:
    ///   - string: The string value to pad
    ///   - vr: The Value Representation (determines padding character)
    /// - Returns: Padded string data
    public func padString(_ string: String, vr: VR) -> Data {
        var data = Data(string.utf8)
        
        // DICOM requires even byte lengths
        if data.count % 2 != 0 {
            // UI uses null padding, others use space padding
            let paddingByte: UInt8 = (vr == .UI) ? 0x00 : 0x20
            data.append(paddingByte)
        }
        
        return data
    }
    
    /// Serializes a string value for writing
    ///
    /// - Parameters:
    ///   - value: The string value
    ///   - vr: The Value Representation
    /// - Returns: Serialized and padded data
    public func serializeString(_ value: String, vr: VR) -> Data {
        return padString(value, vr: vr)
    }
    
    /// Serializes multiple string values with backslash delimiter
    ///
    /// DICOM uses backslash (\) as the delimiter for multi-valued string elements.
    /// Reference: PS3.5 Section 6.2 - Value Multiplicity
    ///
    /// - Parameters:
    ///   - values: Array of string values
    ///   - vr: The Value Representation
    /// - Returns: Serialized and padded data
    public func serializeStrings(_ values: [String], vr: VR) -> Data {
        let joined = values.joined(separator: "\\")
        return padString(joined, vr: vr)
    }
    
    /// Serializes a UInt16 value
    ///
    /// - Parameter value: The UInt16 value
    /// - Returns: 2-byte data in the configured byte order
    public func serializeUInt16(_ value: UInt16) -> Data {
        var data = Data(count: 2)
        if byteOrder == .littleEndian {
            data[0] = UInt8(value & 0xFF)
            data[1] = UInt8((value >> 8) & 0xFF)
        } else {
            data[0] = UInt8((value >> 8) & 0xFF)
            data[1] = UInt8(value & 0xFF)
        }
        return data
    }
    
    /// Serializes multiple UInt16 values
    ///
    /// - Parameter values: Array of UInt16 values
    /// - Returns: Serialized data for all values
    public func serializeUInt16s(_ values: [UInt16]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeUInt16(value))
        }
        return data
    }
    
    /// Serializes a UInt32 value
    ///
    /// - Parameter value: The UInt32 value
    /// - Returns: 4-byte data in the configured byte order
    public func serializeUInt32(_ value: UInt32) -> Data {
        var data = Data(count: 4)
        if byteOrder == .littleEndian {
            data[0] = UInt8(value & 0xFF)
            data[1] = UInt8((value >> 8) & 0xFF)
            data[2] = UInt8((value >> 16) & 0xFF)
            data[3] = UInt8((value >> 24) & 0xFF)
        } else {
            data[0] = UInt8((value >> 24) & 0xFF)
            data[1] = UInt8((value >> 16) & 0xFF)
            data[2] = UInt8((value >> 8) & 0xFF)
            data[3] = UInt8(value & 0xFF)
        }
        return data
    }
    
    /// Serializes multiple UInt32 values
    ///
    /// - Parameter values: Array of UInt32 values
    /// - Returns: Serialized data for all values
    public func serializeUInt32s(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeUInt32(value))
        }
        return data
    }
    
    /// Serializes an Int16 value
    ///
    /// - Parameter value: The Int16 value
    /// - Returns: 2-byte data in the configured byte order
    public func serializeInt16(_ value: Int16) -> Data {
        return serializeUInt16(UInt16(bitPattern: value))
    }
    
    /// Serializes multiple Int16 values
    ///
    /// - Parameter values: Array of Int16 values
    /// - Returns: Serialized data for all values
    public func serializeInt16s(_ values: [Int16]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeInt16(value))
        }
        return data
    }
    
    /// Serializes an Int32 value
    ///
    /// - Parameter value: The Int32 value
    /// - Returns: 4-byte data in the configured byte order
    public func serializeInt32(_ value: Int32) -> Data {
        return serializeUInt32(UInt32(bitPattern: value))
    }
    
    /// Serializes multiple Int32 values
    ///
    /// - Parameter values: Array of Int32 values
    /// - Returns: Serialized data for all values
    public func serializeInt32s(_ values: [Int32]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeInt32(value))
        }
        return data
    }
    
    /// Serializes a Float32 value
    ///
    /// - Parameter value: The Float32 value
    /// - Returns: 4-byte data in the configured byte order
    public func serializeFloat32(_ value: Float32) -> Data {
        return serializeUInt32(value.bitPattern)
    }
    
    /// Serializes multiple Float32 values
    ///
    /// - Parameter values: Array of Float32 values
    /// - Returns: Serialized data for all values
    public func serializeFloat32s(_ values: [Float32]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeFloat32(value))
        }
        return data
    }
    
    /// Serializes a Float64 value
    ///
    /// - Parameter value: The Float64 value
    /// - Returns: 8-byte data in the configured byte order
    public func serializeFloat64(_ value: Float64) -> Data {
        let bits = value.bitPattern
        var data = Data(count: 8)
        if byteOrder == .littleEndian {
            for i in 0..<8 {
                data[i] = UInt8((bits >> (i * 8)) & 0xFF)
            }
        } else {
            for i in 0..<8 {
                data[7 - i] = UInt8((bits >> (i * 8)) & 0xFF)
            }
        }
        return data
    }
    
    /// Serializes multiple Float64 values
    ///
    /// - Parameter values: Array of Float64 values
    /// - Returns: Serialized data for all values
    public func serializeFloat64s(_ values: [Float64]) -> Data {
        var data = Data()
        for value in values {
            data.append(serializeFloat64(value))
        }
        return data
    }
    
    /// Serializes an Attribute Tag value (AT VR)
    ///
    /// AT VR stores tag values as two consecutive UInt16 values.
    /// Reference: PS3.5 Section 6.2 - AT Value Representation
    ///
    /// - Parameter tag: The tag to serialize
    /// - Returns: 4-byte data representing the tag
    public func serializeTag(_ tag: Tag) -> Data {
        var data = Data()
        data.append(serializeUInt16(tag.group))
        data.append(serializeUInt16(tag.element))
        return data
    }
    
    /// Serializes multiple Attribute Tag values
    ///
    /// - Parameter tags: Array of tags to serialize
    /// - Returns: Serialized data for all tags
    public func serializeTags(_ tags: [Tag]) -> Data {
        var data = Data()
        for tag in tags {
            data.append(serializeTag(tag))
        }
        return data
    }
    
    // MARK: - Data Element Serialization
    
    /// Serializes a data element header (tag, VR, length)
    ///
    /// Reference: PS3.5 Section 7.1 - Data Element Structure
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - vr: The Value Representation
    ///   - length: The value length in bytes
    /// - Returns: Serialized header data
    public func serializeElementHeader(tag: Tag, vr: VR, length: UInt32) -> Data {
        var data = Data()
        
        // Write tag (group, element)
        data.append(serializeUInt16(tag.group))
        data.append(serializeUInt16(tag.element))
        
        if explicitVR {
            // Write VR as 2 ASCII characters
            let vrString = vr.rawValue
            data.append(contentsOf: vrString.utf8)
            
            if vr.uses32BitLength {
                // VRs with 32-bit length: 2 reserved bytes + 4-byte length
                data.append(contentsOf: [0x00, 0x00])
                data.append(serializeUInt32(length))
            } else {
                // VRs with 16-bit length
                data.append(serializeUInt16(UInt16(length)))
            }
        } else {
            // Implicit VR: 32-bit length only
            data.append(serializeUInt32(length))
        }
        
        return data
    }
    
    /// Serializes a complete data element
    ///
    /// - Parameter element: The data element to serialize
    /// - Returns: Serialized data element including header and value
    public func serializeElement(_ element: DataElement) -> Data {
        var data = Data()

        // Handle sequences specially
        if element.vr == .SQ {
            data.append(serializeSequence(element))
            return data
        }

        // Handle encapsulated (compressed) pixel data: an undefined-length element
        // carrying a Basic Offset Table + Item-tagged codestream fragments + a
        // Sequence Delimitation Item (PS3.5 A.4). The generic value path below skips
        // undefined-length values, so without this branch the compressed pixels are
        // silently dropped whenever a compressed data set is re-serialized (e.g.
        // dicom-convert transcoding or DICOMFile.write()).
        if element.length == 0xFFFFFFFF,
           let fragments = element.encapsulatedFragments {
            data.append(serializeEncapsulatedPixelData(element, fragments: fragments))
            return data
        }

        // Write header
        data.append(serializeElementHeader(tag: element.tag, vr: element.vr, length: element.length))

        // Write value data, in this writer's byte order: a value parsed from (or built for) the
        // other order is byte-swapped per its VR (PS3.5 2026a 7.3; D206).
        if element.length != 0xFFFFFFFF {
            data.append(Self.value(element.valueData, vr: element.vr, from: element.byteOrder, to: byteOrder))
        }

        return data
    }

    /// The size of one binary value unit that changes with byte order. PS3.5 2026a 7.3 lists the
    /// VRs "that are not a string of characters and consist of multiple bytes": "2-byte US, SS, OW
    /// and each component of AT", "4-byte OF, OL, UL, SL, and FL", "8-byte OD, OV, FD, SV and UV"
    /// (Big Endian itself is retired, A.3, described in PS3.5 2016b). `nil` for a VR whose value
    /// is not byte-swapped (OB, UN, SQ, character strings).
    public static func byteSwapUnit(for vr: VR) -> Int? {
        switch vr {
        case .US, .SS, .OW, .AT: return 2
        case .UL, .SL, .FL, .OF, .OL: return 4
        case .FD, .OD, .OV, .SV, .UV: return 8
        default: return nil
        }
    }

    /// `value` re-expressed in `target` byte order. A value whose length is not a multiple of
    /// the VR's unit is returned unchanged (it is malformed; swapping part of it would hide that).
    public static func value(_ value: Data, vr: VR, from source: ByteOrder, to target: ByteOrder) -> Data {
        guard source != target, let unit = byteSwapUnit(for: vr), value.count % unit == 0 else { return value }
        var bytes = [UInt8](value)
        var i = 0
        while i < bytes.count {
            bytes[i..<(i + unit)].reverse()
            i += unit
        }
        return Data(bytes)
    }

    /// Serializes an element with checked encapsulated frame and size bounds. Sequence
    /// children inherit the same per-Pixel-Data cap. Supply surrounding frame/table
    /// attributes when available, especially for multiple frames with an empty BOT.
    public func serializeCheckedElement(
        _ element: DataElement, maxEncapsulatedBytes: Int = Int(UInt32.max),
        numberOfFrames: Int? = nil, extendedOffsetTableData: Data? = nil,
        extendedOffsetTableLengthsData: Data? = nil, transferSyntax: TransferSyntax? = nil
    ) throws -> Data {
        if element.vr == .SQ {
            var itemsData = Data()
            for item in element.sequenceItems ?? [] {
                let itemData = try serializeCheckedSequenceItem(item, maxEncapsulatedBytes: maxEncapsulatedBytes)
                try appendSequenceBytes(itemData, to: &itemsData)
            }
            var result = serializeElementHeader(tag: element.tag, vr: .SQ, length: UInt32(itemsData.count))
            result.append(itemsData)
            return result
        }
        if element.length == 0xFFFFFFFF, let fragments = element.encapsulatedFragments {
            return try serializeCheckedEncapsulatedPixelData(
                element, fragments: fragments, maxSerializedBytes: maxEncapsulatedBytes,
                numberOfFrames: numberOfFrames, extendedOffsetTableData: extendedOffsetTableData,
                extendedOffsetTableLengthsData: extendedOffsetTableLengthsData, transferSyntax: transferSyntax)
        }
        return try serializeCheckedValue(element)
    }

    /// A known short VR with an oversized value can use UN and a 32-bit length
    /// in Explicit VR (PS3.5 §6.2.2). UN payloads use little-endian ordering.
    private func serializeCheckedValue(_ element: DataElement) throws -> Data {
        let count = element.valueData.count
        guard element.length != UInt32.max, UInt32(exactly: count) == element.length else {
            throw DICOMError.parsingFailed("Value length for \(element.tag) does not match its stored bytes")
        }
        let padding = count % 2
        let (paddedCount, overflow) = count.addingReportingOverflow(padding)
        guard !overflow, let length = UInt32(exactly: paddedCount), length != UInt32.max else {
            throw DICOMError.limitExceeded("Value for \(element.tag) exceeds the defined DICOM Value Length")
        }
        if padding != 0 && element.vr.characterRepertoire == nil && element.vr != .OB && element.vr != .UN {
            throw DICOMError.parsingFailed("Odd-length numeric value for \(element.tag) with VR \(element.vr.rawValue)")
        }
        let needsUN = explicitVR && !element.vr.uses32BitLength && length > UInt32(UInt16.max)
        guard !needsUN || element.tag.group != 0x0002 else {
            throw DICOMError.limitExceeded("File Meta Information value for \(element.tag) exceeds the Explicit VR length field")
        }
        if !needsUN && padding == 0 { return serializeElement(element) }
        let outputVR: VR = needsUN ? .UN : element.vr
        var data = serializeElementHeader(tag: element.tag, vr: outputVR, length: length)
        data.append(Self.value(element.valueData, vr: element.vr, from: element.byteOrder,
                               to: needsUN ? .littleEndian : byteOrder))
        if padding != 0 {
            data.append(element.vr.characterRepertoire != nil && element.vr != .UI ? 0x20 : 0)
        }
        return data
    }

    private func serializeCheckedSequenceItem(_ item: SequenceItem, maxEncapsulatedBytes: Int) throws -> Data {
        var bytes = Data()
        for tag in item.tags {
            guard let element = item[tag] else { continue }
            let checked: Data
            if tag == .pixelData && element.isEncapsulated {
                checked = try serializeCheckedElement(element, maxEncapsulatedBytes: maxEncapsulatedBytes,
                    numberOfFrames: Self.checkedFrameCount(item[.numberOfFrames]),
                    extendedOffsetTableData: item[.extendedOffsetTable]?.valueData,
                    extendedOffsetTableLengthsData: item[.extendedOffsetTableLengths]?.valueData)
            } else {
                checked = try serializeCheckedElement(element, maxEncapsulatedBytes: maxEncapsulatedBytes)
            }
            try appendSequenceBytes(checked, to: &bytes)
        }
        var data = serializeTag(.item)
        data.append(serializeUInt32(UInt32(bytes.count)))
        data.append(bytes)
        return data
    }

    private func appendSequenceBytes(_ bytes: Data, to output: inout Data) throws {
        let (count, overflow) = output.count.addingReportingOverflow(bytes.count)
        guard !overflow, count < Int(UInt32.max) else { throw EncapsulatedOffsetBuildError.sequenceLengthOutOfBounds }
        output.append(bytes)
    }

    package static func checkedFrameCount(_ attribute: DataElement?) throws -> Int {
        guard let attribute else { return 1 }
        guard let text = attribute.stringValue,
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            throw EncapsulatedOffsetBuildError.invalidNumberOfFrames
        }
        return value
    }

    /// Checks item widths, total length and frame boundaries before serializing.
    /// An odd logical fragment can be padded only at the end of a known frame.
    public func serializeCheckedEncapsulatedPixelData(
        _ element: DataElement, fragments: [Data], maxSerializedBytes: Int = Int(UInt32.max),
        numberOfFrames: Int? = nil, extendedOffsetTableData: Data? = nil,
        extendedOffsetTableLengthsData: Data? = nil, transferSyntax: TransferSyntax? = nil
    ) throws -> Data {
        let offsets = element.encapsulatedOffsetTable ?? []
        let checked = try EncapsulatedPixelData.validateCheckedEncapsulatedSerialization(
            fragments: fragments, offsetTableCount: offsets.count,
            maxSerializedBytes: maxSerializedBytes)
        if let syntax = transferSyntax, syntax.isVideo {
            // Video frames share one inter-coded bitstream. Number of Frames
            // describes playback and supplies no fragment offsets (PS3.5 A.4.5–7).
            guard offsets.isEmpty, extendedOffsetTableData == nil, extendedOffsetTableLengthsData == nil else {
                throw DICOMError.parsingFailed("Continuous video Pixel Data requires an empty BOT and no extended offsets")
            }
            guard fragments.count == 1 || syntax.allowsMultipleFragments else {
                throw DICOMError.parsingFailed("This video transfer syntax requires the entire bitstream in one fragment")
            }
            guard fragments.dropLast().allSatisfy({ $0.count.isMultiple(of: 2) }) else {
                throw DICOMError.parsingFailed("An interior video fragment cannot be padded inside the bitstream")
            }
        } else {
            // Without dataset metadata an empty BOT does not prove that an odd
            // nonfinal fragment terminates a frame. Only the last may be padded.
            let inferredCount = offsets.isEmpty ? (extendedOffsetTableData.map { $0.count / 8 } ?? 1) : offsets.count
            _ = try EncapsulatedPixelData.resolveFrameIndex(
                numberOfFrames: numberOfFrames ?? inferredCount, fragments: fragments, offsetTable: offsets,
                extendedOffsetTableData: extendedOffsetTableData,
                extendedOffsetTableLengthsData: extendedOffsetTableLengthsData)
        }
        return serializeEncapsulatedPixelData(element, fragments: fragments, capacity: checked.totalElementByteCount)
    }

    /// Shared byte emitter. The throwing API validates its inputs first. The
    /// original nonthrowing serialization API retains its existing size contract
    /// and does not silently omit a Pixel Data element on a checked-cap refusal.
    private func serializeEncapsulatedPixelData(_ element: DataElement, fragments: [Data], capacity: Int? = nil) -> Data {
        var data = Data()
        if let capacity { data.reserveCapacity(capacity) }
        data.append(serializeTag(element.tag))
        data.append(contentsOf: "OB".utf8)
        data.append(contentsOf: [0x00, 0x00])
        data.append(serializeUInt32(0xFFFFFFFF))

        let offsets = element.encapsulatedOffsetTable ?? []
        data.append(serializeTag(.item))
        data.append(serializeUInt32(UInt32(offsets.count * 4)))
        for offset in offsets { data.append(serializeUInt32(offset)) }
        for fragment in fragments {
            data.append(serializeTag(.item))
            let padding = fragment.count % 2
            data.append(serializeUInt32(UInt32(fragment.count + padding)))
            data.append(fragment)
            if padding != 0 { data.append(0) }
        }
        data.append(serializeTag(.sequenceDelimitationItem))
        data.append(serializeUInt32(0))
        return data
    }

    /// Serializes a sequence element (SQ VR)
    ///
    /// Reference: PS3.5 Section 7.5 - Nesting of Data Sets
    ///
    /// - Parameter element: The sequence element to serialize
    /// - Returns: Serialized sequence data
    private func serializeSequence(_ element: DataElement) -> Data {
        var data = Data()
        
        guard let items = element.sequenceItems else {
            // Empty sequence with explicit length 0
            data.append(serializeElementHeader(tag: element.tag, vr: .SQ, length: 0))
            return data
        }
        
        // Serialize items first to calculate length
        var itemsData = Data()
        for item in items {
            itemsData.append(serializeSequenceItem(item))
        }
        
        // Write sequence header with calculated length
        data.append(serializeElementHeader(tag: element.tag, vr: .SQ, length: UInt32(itemsData.count)))
        data.append(itemsData)
        
        return data
    }
    
    /// Serializes a sequence item
    ///
    /// Reference: PS3.5 Section 7.5.2 - Explicit Length
    ///
    /// - Parameter item: The sequence item to serialize
    /// - Returns: Serialized item data
    public func serializeSequenceItem(_ item: SequenceItem) -> Data {
        var data = Data()
        
        // Serialize all elements in the item
        var elementsData = Data()
        let sortedTags = item.tags.sorted()
        for tag in sortedTags {
            if let element = item[tag] {
                elementsData.append(serializeElement(element))
            }
        }
        
        // Item Tag (FFFE,E000)
        data.append(serializeUInt16(0xFFFE))
        data.append(serializeUInt16(0xE000))
        
        // Item Length
        data.append(serializeUInt32(UInt32(elementsData.count)))
        
        // Item data
        data.append(elementsData)
        
        return data
    }
}

// MARK: - Data Element Creation Helpers

extension DataElement {
    /// Creates a data element with a string value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - vr: The Value Representation
    ///   - value: The string value
    /// - Returns: A new data element
    public static func string(tag: Tag, vr: VR, value: String) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeString(value, vr: vr)
        return DataElement(tag: tag, vr: vr, length: UInt32(valueData.count), valueData: valueData,
                           specificCharacterSet: "ISO_IR 192")
    }
    
    /// Creates a data element with multiple string values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - vr: The Value Representation
    ///   - values: Array of string values
    /// - Returns: A new data element
    public static func strings(tag: Tag, vr: VR, values: [String]) -> DataElement {
        string(tag: tag, vr: vr, value: values.joined(separator: "\\"))
    }
    
    /// Creates a data element with a UInt16 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The UInt16 value
    /// - Returns: A new data element with US VR
    public static func uint16(tag: Tag, value: UInt16) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeUInt16(value)
        return DataElement(tag: tag, vr: .US, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple UInt16 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of UInt16 values
    /// - Returns: A new data element with US VR
    public static func uint16s(tag: Tag, values: [UInt16]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeUInt16s(values)
        return DataElement(tag: tag, vr: .US, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with a UInt32 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The UInt32 value
    /// - Returns: A new data element with UL VR
    public static func uint32(tag: Tag, value: UInt32) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeUInt32(value)
        return DataElement(tag: tag, vr: .UL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple UInt32 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of UInt32 values
    /// - Returns: A new data element with UL VR
    public static func uint32s(tag: Tag, values: [UInt32]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeUInt32s(values)
        return DataElement(tag: tag, vr: .UL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with an Int16 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The Int16 value
    /// - Returns: A new data element with SS VR
    public static func int16(tag: Tag, value: Int16) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeInt16(value)
        return DataElement(tag: tag, vr: .SS, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple Int16 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of Int16 values
    /// - Returns: A new data element with SS VR
    public static func int16s(tag: Tag, values: [Int16]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeInt16s(values)
        return DataElement(tag: tag, vr: .SS, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with an Int32 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The Int32 value
    /// - Returns: A new data element with SL VR
    public static func int32(tag: Tag, value: Int32) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeInt32(value)
        return DataElement(tag: tag, vr: .SL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple Int32 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of Int32 values
    /// - Returns: A new data element with SL VR
    public static func int32s(tag: Tag, values: [Int32]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeInt32s(values)
        return DataElement(tag: tag, vr: .SL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with a Float32 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The Float32 value
    /// - Returns: A new data element with FL VR
    public static func float32(tag: Tag, value: Float32) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeFloat32(value)
        return DataElement(tag: tag, vr: .FL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple Float32 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of Float32 values
    /// - Returns: A new data element with FL VR
    public static func float32s(tag: Tag, values: [Float32]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeFloat32s(values)
        return DataElement(tag: tag, vr: .FL, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with a Float64 value
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - value: The Float64 value
    /// - Returns: A new data element with FD VR
    public static func float64(tag: Tag, value: Float64) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeFloat64(value)
        return DataElement(tag: tag, vr: .FD, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with multiple Float64 values
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - values: Array of Float64 values
    /// - Returns: A new data element with FD VR
    public static func float64s(tag: Tag, values: [Float64]) -> DataElement {
        let writer = DICOMWriter()
        let valueData = writer.serializeFloat64s(values)
        return DataElement(tag: tag, vr: .FD, length: UInt32(valueData.count), valueData: valueData)
    }
    
    /// Creates a data element with raw binary data
    ///
    /// - Parameters:
    ///   - tag: The data element tag
    ///   - vr: The Value Representation (typically OB or OW)
    ///   - data: The raw binary data
    /// - Returns: A new data element
    public static func data(tag: Tag, vr: VR, data: Data) -> DataElement {
        // Ensure even length by padding if necessary
        var paddedData = data
        if paddedData.count % 2 != 0 {
            paddedData.append(0x00)
        }
        return DataElement(tag: tag, vr: vr, length: UInt32(paddedData.count), valueData: paddedData)
    }

    /// Creates an Attribute Tag (AT) data element holding a single tag value.
    ///
    /// An AT value is encoded as two consecutive 16-bit unsigned integers — the
    /// group number followed by the element number — each in the transfer syntax's
    /// byte order. This is the encoding required by, for example,
    /// Frame Increment Pointer (0028,0009).
    ///
    /// Reference: PS3.5 Section 6.2, Table 6.2-1 (AT Value Representation)
    ///
    /// - Parameters:
    ///   - tag: The data element tag to create
    ///   - value: The tag to encode as the element's value
    /// - Returns: A new data element with AT VR
    public static func attributeTag(tag: Tag, value: Tag) -> DataElement {
        return attributeTags(tag: tag, values: [value])
    }

    /// Creates an Attribute Tag (AT) data element holding one or more tag values.
    ///
    /// Reference: PS3.5 Section 6.2, Table 6.2-1 (AT Value Representation)
    ///
    /// - Parameters:
    ///   - tag: The data element tag to create
    ///   - values: The tags to encode as the element's value
    /// - Returns: A new data element with AT VR
    public static func attributeTags(tag: Tag, values: [Tag]) -> DataElement {
        let writer = DICOMWriter()
        var valueData = Data()
        for value in values {
            valueData.append(writer.serializeUInt16(value.group))
            valueData.append(writer.serializeUInt16(value.element))
        }
        return DataElement(tag: tag, vr: .AT, length: UInt32(valueData.count), valueData: valueData)
    }
}
