// NEMA-verified: 2026a, checked 2026-09-29 — PS3.5 2026a 7.1.2, 7.1.3, 7.5, A.4 and A.5 encoding rules read clause by clause (item and delimiter tags, undefined length, Basic Offset Table, fragments, raw DEFLATE); the multi-VR first-VR heuristic is recorded
import Foundation
import DICOMCore
import DICOMDictionary

/// Internal parser for DICOM files
///
/// Parses DICOM Part 10 files with supported transfer syntaxes including:
/// - Explicit VR Little Endian (1.2.840.10008.1.2.1)
/// - Implicit VR Little Endian (1.2.840.10008.1.2)
/// - Explicit VR Big Endian (1.2.840.10008.1.2.2) - Retired
/// - Deflated Explicit VR Little Endian (1.2.840.10008.1.2.1.99)
///
/// Reference: PS3.10 Section 7 - DICOM File Format
struct DICOMParser {
    private var data: Data
    private var offset: Int
    private let options: ParsingOptions

    /// Current sequence/item nesting depth; bounded by `options.maxSequenceDepth`
    /// to prevent stack overflow on maliciously nested sequences.
    private var sequenceDepth: Int = 0

    /// Total elements parsed (including nested); bounded by `options.maxTotalElements`.
    private var totalElementCount: Int = 0

    init(data: Data, options: ParsingOptions = .default) {
        self.data = data
        self.offset = 0
        self.options = options
    }

    // MARK: - Resource Limits

    /// Counts one parsed element against the total-element budget.
    private mutating func countElement() throws {
        totalElementCount += 1
        if let maxTotal = options.maxTotalElements, totalElementCount > maxTotal {
            throw DICOMError.limitExceeded(
                "Element count exceeds maxTotalElements (\(maxTotal))")
        }
    }

    /// Validates a defined value length against the per-element ceiling.
    private func checkElementLength(_ length: UInt32, tag: Tag) throws {
        if let maxLength = options.maxElementLength, Int(length) > maxLength {
            throw DICOMError.limitExceeded(
                "Element \(tag) declares length \(length), exceeding maxElementLength (\(maxLength))")
        }
    }
    
    /// Parses File Meta Information elements
    ///
    /// File Meta Information elements are always encoded with Explicit VR Little Endian,
    /// regardless of the transfer syntax used for the main data set.
    /// Reference: PS3.10 Section 7.1
    mutating func parseFileMetaInformation(startOffset: Int) throws -> DataSet {
        offset = startOffset
        var elements: [DataElement] = []
        
        // File Meta Information starts after DICM prefix (offset 132)
        // Group 0002 elements only
        while offset < data.count {
            // Peek at the group number (always Little Endian for File Meta Information)
            guard let groupNumber = data.readUInt16LE(at: offset) else {
                break
            }
            
            // Stop when we're past group 0002
            if groupNumber != 0x0002 {
                break
            }
            
            // Parse this element (File Meta Info is always Explicit VR Little Endian)
            guard let element = try? parseExplicitVRElement(byteOrder: .littleEndian) else {
                break
            }
            
            elements.append(element)
        }
        
        return DataSet(elements: elements)
    }
    
    /// Parses main data set elements
    ///
    /// Parses data elements using the specified transfer syntax encoding.
    /// Reference: PS3.5 Section 7.1 - Data Element Structure
    mutating func parseDataSet(transferSyntaxUID: String) throws -> DataSet {
        return try parseDataSet(startOffset: offset, transferSyntaxUID: transferSyntaxUID)
    }
    
    /// Parses main data set elements starting from a specified offset
    ///
    /// Parses data elements using the specified transfer syntax encoding.
    /// Used for legacy DICOM files that don't have a preamble.
    /// Reference: PS3.5 Section 7.1 - Data Element Structure
    mutating func parseDataSet(startOffset: Int, transferSyntaxUID: String) throws -> DataSet {
        offset = startOffset
        
        // Determine transfer syntax
        guard let transferSyntax = TransferSyntax.from(uid: transferSyntaxUID) else {
            throw DICOMError.unsupportedTransferSyntax(transferSyntaxUID)
        }
        
        // Handle deflated data
        if transferSyntax.isDeflated {
            try decompressDeflatedData()
        }
        
        let isExplicitVR = transferSyntax.isExplicitVR
        let byteOrder = transferSyntax.byteOrder
        let isEncapsulated = transferSyntax.isEncapsulated
        
        var elements: [DataElement] = []
        var elementCount = 0
        
        // Parse elements until we reach the end or pixel data
        while offset < data.count {
            // Check max elements limit
            if let maxElements = options.maxElements, elementCount >= maxElements {
                break
            }
            
            // Check for pixel data (7FE0,0010)
            guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
                break
            }
            guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                break
            }
            
            let currentTag = Tag(group: groupNumber, element: elementNumber)
            
            // Check stopAfterTag option
            if let stopTag = options.stopAfterTag, currentTag == stopTag {
                // Parse this element and stop
                let element: DataElement
                if isExplicitVR {
                    guard let parsed = try? parseExplicitVRElement(byteOrder: byteOrder) else {
                        break
                    }
                    element = parsed
                } else {
                    guard let parsed = try? parseImplicitVRElement(byteOrder: byteOrder) else {
                        break
                    }
                    element = parsed
                }
                elements.append(element)
                elementCount += 1
                break
            }
            
            // Handle pixel data based on parsing mode
            if groupNumber == 0x7FE0 && elementNumber == 0x0010 {
                switch options.mode {
                case .metadataOnly:
                    // Skip pixel data entirely
                    break
                    
                case .lazyPixelData:
                    // Parse pixel data tag but don't load the value
                    let pixelDataElement = try parsePixelDataMetadataOnly(
                        isExplicitVR: isExplicitVR,
                        byteOrder: byteOrder,
                        isEncapsulated: isEncapsulated
                    )
                    elements.append(pixelDataElement)
                    break
                    
                case .full:
                    // Parse pixel data element fully
                    let pixelDataElement: DataElement
                    if isEncapsulated {
                        pixelDataElement = try parseEncapsulatedPixelData(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
                    } else {
                        if isExplicitVR {
                            guard let parsed = try? parseExplicitVRElement(byteOrder: byteOrder) else {
                                break
                            }
                            pixelDataElement = parsed
                        } else {
                            guard let parsed = try? parseImplicitVRElement(byteOrder: byteOrder) else {
                                break
                            }
                            pixelDataElement = parsed
                        }
                    }
                    elements.append(pixelDataElement)
                    break
                }
                
                // Always stop after pixel data
                break
            }
            
            // Parse this element.  Save the offset before attempting so
            // we can try to skip over a problematic element on failure
            // rather than silently losing every element that follows.
            let savedOffset = offset
            let element: DataElement
            if isExplicitVR {
                do {
                    element = try parseExplicitVRElement(byteOrder: byteOrder)
                } catch DICOMError.limitExceeded(let message) {
                    // Limit violations are structural safety failures, not
                    // recoverable single-element corruption — never skip past them.
                    throw DICOMError.limitExceeded(message)
                } catch {
                    // Restore offset and try to skip the element
                    offset = savedOffset
                    if trySkipElement(isExplicitVR: true, byteOrder: byteOrder) {
                        continue
                    }
                    break
                }
            } else {
                do {
                    element = try parseImplicitVRElement(byteOrder: byteOrder)
                } catch DICOMError.limitExceeded(let message) {
                    throw DICOMError.limitExceeded(message)
                } catch {
                    offset = savedOffset
                    if trySkipElement(isExplicitVR: false, byteOrder: byteOrder) {
                        continue
                    }
                    break
                }
            }
            
            elements.append(element)
            elementCount += 1
        }
        
        return DataSet(elements: elements)
    }
    
    // MARK: - Encapsulated Pixel Data Parsing
    
    /// Parses encapsulated (compressed) pixel data
    ///
    /// Encapsulated pixel data is stored as a sequence of fragments with an optional
    /// Basic Offset Table. The structure is:
    /// - Pixel Data Tag (7FE0,0010)
    /// - VR (OB or OW) and Length (undefined = FFFFFFFF)
    /// - Item Tag (FFFE,E000) + Length + Basic Offset Table (first item, may be empty)
    /// - Item Tag (FFFE,E000) + Length + Fragment data (repeated for each fragment)
    /// - Sequence Delimitation Item (FFFE,E0DD)
    ///
    /// Reference: PS3.5 Section A.4 - Transfer Syntaxes For Encapsulation of Encoded Pixel Data
    private mutating func parseEncapsulatedPixelData(isExplicitVR: Bool, byteOrder: ByteOrder) throws -> DataElement {
        // Read tag (should be 7FE0,0010)
        guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read VR and length
        let vr: VR
        let valueLength: UInt32
        
        if isExplicitVR {
            guard offset + 2 <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let vrByte0 = data[offset]
            let vrByte1 = data[offset + 1]
            offset += 2
            
            guard let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
                  let parsedVR = VR(rawValue: vrString) else {
                // Default to OB for pixel data if VR is invalid
                vr = .OB
                offset -= 2 // backtrack
                valueLength = 0xFFFFFFFF
                return DataElement(tag: tag, vr: vr, length: valueLength, valueData: Data(), byteOrder: byteOrder)
            }
            vr = parsedVR
            
            // Skip 2 reserved bytes and read 4-byte length
            offset += 2
            guard let length32 = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let length32 = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        }
        
        // For encapsulated pixel data, the length should be undefined (0xFFFFFFFF)
        guard valueLength == 0xFFFFFFFF else {
            // Not actually encapsulated, treat as regular pixel data
            try checkElementLength(valueLength, tag: tag)
            guard offset + Int(valueLength) <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }
            let valueData = data.subdata(in: offset..<offset + Int(valueLength))
            offset += Int(valueLength)
            return DataElement(tag: tag, vr: vr, length: valueLength, valueData: valueData, byteOrder: byteOrder)
        }
        
        // Parse the Basic Offset Table (first item)
        var offsetTable: [UInt32] = []
        var fragments: [Data] = []
        
        // Read first item (Basic Offset Table)
        guard let botItemTag = readItemTag(byteOrder: byteOrder) else {
            throw DICOMError.parsingFailed("Expected Item tag for Basic Offset Table")
        }
        
        guard botItemTag == .item else {
            throw DICOMError.parsingFailed("Expected Item tag (FFFE,E000), found \(botItemTag)")
        }
        offset += 4
        
        guard let botLength = readUInt32(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        // Parse offset table if present
        if botLength > 0 {
            let numOffsets = Int(botLength) / 4
            for _ in 0..<numOffsets {
                guard let offsetValue = readUInt32(at: offset, byteOrder: .littleEndian) else {
                    throw DICOMError.unexpectedEndOfData
                }
                offsetTable.append(offsetValue)
                offset += 4
            }
        }
        
        // Parse fragments until Sequence Delimitation Item
        while offset < data.count {
            guard let itemTag = readItemTag(byteOrder: byteOrder) else {
                break
            }
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                offset += 4 // Skip tag
                offset += 4 // Skip length (should be 0)
                break
            }
            
            // Should be an Item tag
            guard itemTag == .item else {
                throw DICOMError.parsingFailed("Expected Item or Sequence Delimitation tag, found \(itemTag)")
            }
            offset += 4
            
            guard let fragmentLength = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4

            try checkElementLength(fragmentLength, tag: tag)
            if let maxFragments = options.maxFragmentCount, fragments.count >= maxFragments {
                throw DICOMError.limitExceeded(
                    "Encapsulated fragment count exceeds maxFragmentCount (\(maxFragments))")
            }

            guard offset + Int(fragmentLength) <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }

            let fragmentData = data.subdata(in: offset..<offset + Int(fragmentLength))
            fragments.append(fragmentData)
            offset += Int(fragmentLength)
        }
        
        return DataElement(
            tag: tag,
            vr: vr,
            length: valueLength,
            valueData: Data(),
            encapsulatedFragments: fragments,
            encapsulatedOffsetTable: offsetTable,
            byteOrder: byteOrder
        )
    }
    
    /// Parses pixel data metadata without loading the pixel values (lazy loading)
    ///
    /// This method reads the tag, VR, and length of pixel data but skips the actual
    /// pixel values. This significantly reduces memory usage when pixel data is not needed.
    ///
    /// - Parameters:
    ///   - isExplicitVR: Whether the transfer syntax uses explicit VR
    ///   - byteOrder: Byte order for reading
    ///   - isEncapsulated: Whether pixel data is encapsulated (compressed)
    /// - Returns: Data element with pixel data tag but empty value
    /// - Throws: DICOMError if parsing fails
    private mutating func parsePixelDataMetadataOnly(
        isExplicitVR: Bool,
        byteOrder: ByteOrder,
        isEncapsulated: Bool
    ) throws -> DataElement {
        // Read tag (should be 7FE0,0010)
        guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read VR and length
        let vr: VR
        let valueLength: UInt32
        
        if isExplicitVR {
            guard offset + 2 <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let vrByte0 = data[offset]
            let vrByte1 = data[offset + 1]
            offset += 2
            
            guard let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
                  let parsedVR = VR(rawValue: vrString) else {
                // Default to OB for pixel data if VR is invalid
                vr = .OB
                offset -= 2 // backtrack
                valueLength = 0
                return DataElement(tag: tag, vr: vr, length: 0, valueData: Data(), byteOrder: byteOrder)
            }
            vr = parsedVR
            
            // Skip 2 reserved bytes and read 4-byte length
            offset += 2
            guard let length32 = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let length32 = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        }
        
        // Skip the actual pixel data value
        if valueLength != 0xFFFFFFFF {
            // Defined length - skip it
            offset += Int(valueLength)
        } else {
            // Undefined length (encapsulated) - skip to sequence delimiter
            while offset < data.count {
                guard let itemTag = readItemTag(byteOrder: byteOrder) else {
                    break
                }
                
                if itemTag == .sequenceDelimitationItem {
                    offset += 4 // Skip tag
                    offset += 4 // Skip length
                    break
                }
                
                guard itemTag == .item else {
                    throw DICOMError.parsingFailed("Expected Item or Sequence Delimitation tag")
                }
                offset += 4
                
                guard let fragmentLength = readUInt32(at: offset, byteOrder: byteOrder) else {
                    throw DICOMError.unexpectedEndOfData
                }
                offset += 4
                offset += Int(fragmentLength)
            }
        }
        
        // Return element with metadata but no value data
        return DataElement(tag: tag, vr: vr, length: valueLength, valueData: Data(), byteOrder: byteOrder)
    }
    
    /// Reads an Item or Delimiter tag
    private func readItemTag(byteOrder: ByteOrder) -> Tag? {
        guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            return nil
        }
        return Tag(group: groupNumber, element: elementNumber)
    }

    // MARK: - Error Recovery

    /// Attempts to skip over a problematic data element by reading its tag
    /// and length, then advancing past its value bytes.
    ///
    /// This provides resilience when a single element fails to parse —
    /// the parser can skip it and continue reading subsequent elements
    /// instead of losing all remaining data.
    ///
    /// - Parameters:
    ///   - isExplicitVR: Whether the element uses explicit VR encoding.
    ///   - byteOrder: Byte order for reading multi-byte values.
    /// - Returns: `true` if the skip succeeded and parsing can continue.
    private mutating func trySkipElement(isExplicitVR: Bool, byteOrder: ByteOrder) -> Bool {
        // Need at least tag (4 bytes) + length field
        guard offset + 8 <= data.count else { return false }

        // Skip the tag (4 bytes)
        offset += 4

        if isExplicitVR {
            // Read VR (2 bytes)
            guard offset + 2 <= data.count else { return false }
            let vrByte0 = data[offset]
            let vrByte1 = data[offset + 1]
            offset += 2

            let vr: VR
            if let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
               let parsedVR = VR(rawValue: vrString) {
                vr = parsedVR
            } else {
                vr = .UN
            }

            if vr.uses32BitLength {
                // Skip 2 reserved bytes + read 4-byte length
                guard offset + 6 <= data.count else { return false }
                offset += 2
                guard let length = readUInt32(at: offset, byteOrder: byteOrder) else { return false }
                offset += 4
                if length == 0xFFFFFFFF { return false } // Can't skip undefined length
                guard offset + Int(length) <= data.count else { return false }
                offset += Int(length)
            } else {
                // Read 2-byte length
                guard let length = readUInt16(at: offset, byteOrder: byteOrder) else { return false }
                offset += 2
                guard offset + Int(length) <= data.count else { return false }
                offset += Int(length)
            }
        } else {
            // Implicit VR: 4-byte length
            guard let length = readUInt32(at: offset, byteOrder: byteOrder) else { return false }
            offset += 4
            if length == 0xFFFFFFFF { return false } // Can't skip undefined length
            guard offset + Int(length) <= data.count else { return false }
            offset += Int(length)
        }

        return true
    }
    
    // MARK: - Byte Order Helpers
    
    /// Reads a 16-bit unsigned integer with the specified byte order
    private func readUInt16(at offset: Int, byteOrder: ByteOrder) -> UInt16? {
        switch byteOrder {
        case .littleEndian:
            return data.readUInt16LE(at: offset)
        case .bigEndian:
            return data.readUInt16BE(at: offset)
        }
    }
    
    /// Reads a 32-bit unsigned integer with the specified byte order
    private func readUInt32(at offset: Int, byteOrder: ByteOrder) -> UInt32? {
        switch byteOrder {
        case .littleEndian:
            return data.readUInt32LE(at: offset)
        case .bigEndian:
            return data.readUInt32BE(at: offset)
        }
    }
    
    // MARK: - Deflate Decompression
    
    /// Decompresses deflated data starting at the current offset
    ///
    /// The File Meta Information is not deflated, only the Data Set portion.
    /// Reference: PS3.5 Section A.5
    private mutating func decompressDeflatedData() throws {
        // Get the deflated portion (everything from current offset to end)
        let deflatedData = data.subdata(in: offset..<data.count)

        // Inflate strictly (PS3.5 A.5): a truncated, corrupt or over-long stream,
        // trailing bytes or an inflated size beyond the option limit all fail the
        // read instead of yielding a silently truncated Data Set.
        let decompressedData: Data
        do {
            decompressedData = try DeflatedDataSet.inflate(
                deflatedData, maximumOutputByteCount: options.maximumInflatedByteCount)
        } catch let failure as DeflatedDataSet.Failure {
            throw DICOMError.parsingFailed("Failed to inflate deflated data set: \(failure)")
        }
        
        // Replace the data from current offset with decompressed data
        let headerData = data.subdata(in: 0..<offset)
        data = headerData + decompressedData
    }
    
    /// Parses a single data element with Implicit VR encoding
    ///
    /// In Implicit VR encoding, the VR is not explicitly specified in the data stream
    /// and must be determined from the Data Element Dictionary.
    /// Reference: PS3.5 Section 7.1.3 - Data Element Structure with Implicit VR
    private mutating func parseImplicitVRElement(byteOrder: ByteOrder) throws -> DataElement {
        // Read tag (4 bytes)
        guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read value length (4 bytes) - Implicit VR always uses 32-bit length
        // Reference: PS3.5 Section 7.1.3
        guard let valueLength = readUInt32(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        // Look up VR from the dictionary
        // If not found, use UN (Unknown) per PS3.5 Section 6.2.2
        let vr: VR
        if let entry = DataElementDictionary.lookup(tag: tag) {
            vr = entry.vr.first ?? .UN
        } else {
            // For unknown tags (both private and standard), use UN
            vr = .UN
        }
        
        // Handle sequence elements (SQ VR)
        if vr == .SQ {
            return try parseSequenceElement(tag: tag, vr: vr, valueLength: valueLength, isExplicitVR: false, byteOrder: byteOrder)
        }
        
        // Handle undefined length for non-sequence elements.
        // Per PS3.5 Annex E, elements with undefined length should be
        // treated as sequences — commonly private sequence data whose
        // actual VR (SQ) is not in the reader's data dictionary.
        if valueLength == 0xFFFFFFFF {
            return try parseSequenceElement(
                tag: tag, vr: vr, valueLength: valueLength,
                isExplicitVR: false, byteOrder: byteOrder
            )
        }

        try countElement()
        try checkElementLength(valueLength, tag: tag)

        guard offset + Int(valueLength) <= data.count else {
            throw DICOMError.unexpectedEndOfData
        }

        let valueData = data.subdata(in: offset..<offset + Int(valueLength))
        offset += Int(valueLength)

        return DataElement(tag: tag, vr: vr, length: valueLength, valueData: valueData, byteOrder: byteOrder)
    }
    
    /// Parses a single data element with Explicit VR encoding
    ///
    /// Reference: PS3.5 Section 7.1.2 - Data Element Structure with Explicit VR
    private mutating func parseExplicitVRElement(byteOrder: ByteOrder) throws -> DataElement {
        // Read tag (4 bytes)
        guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read VR (2 bytes, ASCII characters)
        guard offset + 2 <= data.count else {
            throw DICOMError.unexpectedEndOfData
        }
        
        let vrByte0 = data[offset]
        let vrByte1 = data[offset + 1]
        offset += 2
        
        let vr: VR
        if let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
           let parsedVR = VR(rawValue: vrString) {
            vr = parsedVR
        } else {
            // Unknown or invalid VR - treat as UN (Unknown) for robustness
            // This allows parsing non-conformant DICOM files that may have
            // vendor-specific or malformed VR codes
            vr = .UN
        }
        
        // Read value length
        // For VRs with 32-bit length: skip 2 reserved bytes, then read 4-byte length
        // For VRs with 16-bit length: read 2-byte length
        // Reference: PS3.5 Section 7.1.2
        let valueLength: UInt32
        if vr.uses32BitLength {
            // Skip 2 reserved bytes
            offset += 2
            
            guard let length32 = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            guard let length16 = readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 2
            valueLength = UInt32(length16)
        }
        
        // Handle sequence elements (SQ VR)
        if vr == .SQ {
            return try parseSequenceElement(tag: tag, vr: vr, valueLength: valueLength, isExplicitVR: true, byteOrder: byteOrder)
        }
        
        // Handle undefined length for non-sequence elements.
        // Per PS3.5 Annex E, elements with VR = UN and undefined
        // length should be treated as sequences.  This commonly
        // occurs for private sequence data whose actual VR (SQ) is
        // not in the reader's data dictionary.
        if valueLength == 0xFFFFFFFF {
            return try parseSequenceElement(
                tag: tag, vr: vr, valueLength: valueLength,
                isExplicitVR: true, byteOrder: byteOrder
            )
        }

        try countElement()
        try checkElementLength(valueLength, tag: tag)

        guard offset + Int(valueLength) <= data.count else {
            throw DICOMError.unexpectedEndOfData
        }

        let valueData = data.subdata(in: offset..<offset + Int(valueLength))
        offset += Int(valueLength)

        return DataElement(tag: tag, vr: vr, length: valueLength, valueData: valueData, byteOrder: byteOrder)
    }
    
    // MARK: - Sequence Parsing
    
    /// Parses a sequence element (SQ VR) and its items
    ///
    /// Sequences can have either explicit length or undefined length (0xFFFFFFFF).
    /// Each item in the sequence is delimited by Item tags (FFFE,E000).
    /// Undefined length sequences end with Sequence Delimitation Item (FFFE,E0DD).
    ///
    /// Reference: PS3.5 Section 7.5 - Nesting of Data Sets
    private mutating func parseSequenceElement(tag: Tag, vr: VR, valueLength: UInt32, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> DataElement {
        // Bound recursion: every nesting cycle (sequence → item → element →
        // sequence) passes through here. Without this guard a crafted file with
        // deeply nested (undefined-length) sequences overflows the stack.
        sequenceDepth += 1
        defer { sequenceDepth -= 1 }
        if sequenceDepth > options.maxSequenceDepth {
            throw DICOMError.limitExceeded(
                "Sequence nesting depth exceeds maxSequenceDepth (\(options.maxSequenceDepth))")
        }
        try countElement()

        let startOffset = offset
        var sequenceItems: [SequenceItem] = []
        
        if valueLength == 0xFFFFFFFF {
            // Undefined length sequence - parse until Sequence Delimitation Item
            sequenceItems = try parseUndefinedLengthSequence(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        } else {
            // Explicit length sequence. Clamp to the input bounds: a declared
            // length larger than the remaining data would otherwise push
            // `offset` past `data.count` and crash the raw-value subdata below.
            let endOffset = min(offset + Int(valueLength), data.count)
            sequenceItems = try parseExplicitLengthSequence(endOffset: endOffset, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        }
        
        // Get the raw value data (for completeness). Clamp both bounds: on
        // truncated input the delimiter-skip paths can leave `offset` a few
        // bytes past `data.count`, and an unclamped range would trap.
        let rawEnd = min(offset, data.count)
        let valueData = startOffset <= rawEnd
            ? data.subdata(in: startOffset..<rawEnd)
            : Data()
        
        return DataElement(
            tag: tag,
            vr: vr,
            length: valueLength,
            valueData: valueData,
            sequenceItems: sequenceItems,
            byteOrder: byteOrder
        )
    }
    
    /// Parses a sequence with explicit length
    ///
    /// The sequence ends when we reach the specified end offset.
    /// Reference: PS3.5 Section 7.5.2
    private mutating func parseExplicitLengthSequence(endOffset: Int, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        while offset < endOffset && offset < data.count {
            // Read item tag
            guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
                break
            }
            guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                break
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                // Not an item tag - we're done with the sequence
                break
            }
            
            offset += 4
            
            // Read item length
            guard let itemLength = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            
            // Parse item contents
            let item = try parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
            items.append(item)
        }
        
        // Ensure we've consumed all the sequence data
        if offset < endOffset {
            offset = endOffset
        }
        
        return items
    }
    
    /// Parses a sequence with undefined length
    ///
    /// The sequence ends with Sequence Delimitation Item (FFFE,E0DD).
    /// Reference: PS3.5 Section 7.5.1
    private mutating func parseUndefinedLengthSequence(isExplicitVR: Bool, byteOrder: ByteOrder) throws -> [SequenceItem] {
        var items: [SequenceItem] = []
        
        while offset < data.count {
            // Read tag
            guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                offset += 4
                // Read and skip the length (should be 0)
                offset += 4
                break
            }
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                throw DICOMError.parsingFailed("Expected Item tag (FFFE,E000) in sequence, found \(itemTag)")
            }
            
            offset += 4
            
            // Read item length
            guard let itemLength = readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            
            // Parse item contents
            let item = try parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
            items.append(item)
        }
        
        return items
    }
    
    /// Parses a single sequence item
    ///
    /// Items can have explicit length or undefined length (0xFFFFFFFF).
    /// Undefined length items end with Item Delimitation Item (FFFE,E00D).
    ///
    /// Reference: PS3.5 Section 7.5.2 & 7.5.3
    private mutating func parseSequenceItem(itemLength: UInt32, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> SequenceItem {
        var elements: [DataElement] = []
        
        if itemLength == 0xFFFFFFFF {
            // Undefined length item - parse until Item Delimitation Item
            elements = try parseUndefinedLengthItem(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        } else {
            // Explicit length item — clamp to input bounds (see
            // parseSequenceElement): an oversized declared item length must
            // not advance `offset` past `data.count`.
            let itemEndOffset = min(offset + Int(itemLength), data.count)
            elements = try parseExplicitLengthItem(endOffset: itemEndOffset, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        }
        
        return SequenceItem(elements: elements)
    }
    
    /// Parses an item with explicit length
    private mutating func parseExplicitLengthItem(endOffset: Int, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> [DataElement] {
        var elements: [DataElement] = []
        
        while offset < endOffset && offset < data.count {
            let element: DataElement
            if isExplicitVR {
                element = try parseExplicitVRElement(byteOrder: byteOrder)
            } else {
                element = try parseImplicitVRElement(byteOrder: byteOrder)
            }
            elements.append(element)
        }
        
        // Ensure we've consumed all the item data
        if offset < endOffset {
            offset = endOffset
        }
        
        return elements
    }
    
    /// Parses an item with undefined length
    ///
    /// Ends with Item Delimitation Item (FFFE,E00D).
    private mutating func parseUndefinedLengthItem(isExplicitVR: Bool, byteOrder: ByteOrder) throws -> [DataElement] {
        var elements: [DataElement] = []
        
        while offset < data.count {
            // Peek at tag
            guard let groupNumber = readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            guard let elementNumber = readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let nextTag = Tag(group: groupNumber, element: elementNumber)
            
            // Check for Item Delimitation Item
            if nextTag == .itemDelimitationItem {
                offset += 4
                // Read and skip the length (should be 0)
                offset += 4
                break
            }
            
            // Parse the element
            let element: DataElement
            if isExplicitVR {
                element = try parseExplicitVRElement(byteOrder: byteOrder)
            } else {
                element = try parseImplicitVRElement(byteOrder: byteOrder)
            }
            elements.append(element)
        }
        
        return elements
    }
}

// MARK: - Data Decompression Extension

#if canImport(Compression)
import Compression

extension Data {
    /// Compresses data using the raw deflate algorithm (RFC 1951).
    ///
    /// Produces the exact bitstream `DeflatedDataSet.inflate` consumes — raw DEFLATE with no
    /// zlib header/trailer (Apple's `COMPRESSION_ZLIB` operates on raw DEFLATE),
    /// so the two are a faithful inverse pair. Used to write the Data Set of a
    /// Deflated Explicit VR Little Endian file (the File Meta Information is never
    /// deflated). Returns nil if encoding fails.
    /// Reference: PS3.5 Section A.5 - Deflated Explicit VR Little Endian
    func deflateCompressed() -> Data? {
        if isEmpty { return Data() }
        return self.withUnsafeBytes { sourceBuffer -> Data? in
            guard let sourcePointer = sourceBuffer.baseAddress else {
                return nil
            }

            // Deflate output is bounded by input + ~0.1% + a few bytes per 64 KB
            // stored block; a 1.5× buffer + 64 B is always sufficient and avoids a
            // spurious 0-return on incompressible data (e.g. uncompressed pixels).
            let destinationCapacity = Swift.max(count + count / 2 + 64, 1024)
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
            defer { destinationBuffer.deallocate() }

            let compressedSize = compression_encode_buffer(
                destinationBuffer,
                destinationCapacity,
                sourcePointer.assumingMemoryBound(to: UInt8.self),
                count,
                nil,
                COMPRESSION_ZLIB
            )

            guard compressedSize > 0 else {
                return nil
            }

            return Data(bytes: destinationBuffer, count: compressedSize)
        }
    }
}

#else

extension Data {
    /// Compresses data using the deflate algorithm (RFC 1951)
    ///
    /// On platforms without Compression framework, this returns nil so callers can
    /// surface a clear "deflate unsupported on this platform" error rather than
    /// writing a mislabeled file.
    /// Reference: PS3.5 Section A.5 - Deflated Explicit VR Little Endian
    func deflateCompressed() -> Data? {
        return nil
    }
}

#endif
