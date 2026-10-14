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
    private var data: DICOMParserInput
    private var offset: Int
    private let options: ParsingOptions
    private let capture: BoundedParseCapture?
    private var isStrict: Bool { options.validationPolicy == .strict }
    private var totalElements = 0
    private var sequenceDepth = 0
    private var sequenceItems = 0
    private var materializedValueBytes = 0

    /// Subtraction before addition prevents counter overflow even with Int.max limits.
    private static func reserve(_ count: Int, used: inout Int, limit: Int,
                                resource: StrictParsingError.Resource) throws {
        guard count >= 0, used >= 0, used <= limit, count <= limit - used else {
            throw StrictParsingError.resourceLimitExceeded(resource: resource, limit: limit)
        }
        used += count
    }

    private mutating func reserveElement() throws {
        if capture != nil { try Task.checkCancellation() }
        if isStrict {
            try Self.reserve(1, used: &totalElements,
                             limit: options.strictResourceLimits.maximumTotalElements,
                             resource: .totalElements)
        }
    }

    private mutating func reserveValueBytes(_ count: Int) throws {
        if isStrict {
            try Self.reserve(count, used: &materializedValueBytes,
                             limit: options.strictResourceLimits.maximumMaterializedValueBytes,
                             resource: .materializedValueBytes)
        }
    }

    private func valueEndOffset(length: UInt32) throws -> Int {
        if isStrict {
            guard offset >= 0, offset <= data.count, Int(length) <= data.count - offset else {
                throw DICOMError.unexpectedEndOfData
            }
        }
        return offset + Int(length)
    }

    private func record(_ tag: Tag, at elementOffset: Int, in seen: inout Set<Tag>) throws {
        if isStrict, let capture { try capture.record(tag, at: elementOffset); return }
        if isStrict && !seen.insert(tag).inserted {
            throw StrictParsingError.duplicateTag(tag: tag, offset: elementOffset)
        }
    }

    private func requireBoundary(_ endOffset: Int) throws {
        if isStrict && (endOffset < offset || endOffset > data.count) {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Declared scope boundary exceeds available data")
        }
    }

    private func requireDelimiterLength(byteOrder: ByteOrder) throws {
        if isStrict {
            guard let length = try readUInt32(at: offset + 4, byteOrder: byteOrder), length == 0 else {
                throw StrictParsingError.malformedStructure(offset: offset, reason: "Missing or nonzero delimiter length")
            }
        }
    }

    private func validateLength(_ length: UInt32) throws {
        if isStrict && length != 0xFFFFFFFF && length % 2 != 0 {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Odd value length")
        }
    }

    /// Maintained general element limit, independent of the strict-policy cap.
    private var totalElementCount: Int = 0
    init(data: Data, options: ParsingOptions = .default) {
        self.data = DICOMParserInput(data: data)
        self.offset = 0
        self.options = options
        self.capture = nil
    }

    init(source: any DICOMVerifiedByteSource, options: ParsingOptions, capture: BoundedParseCapture) {
        self.data = DICOMParserInput(source: source)
        self.offset = 0
        self.options = options
        self.capture = capture
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
        var seen = Set<Tag>()
        var declaredMetaEnd: Int?
        
        // File Meta Information starts after DICM prefix (offset 132)
        // Group 0002 elements only
        while offset < data.count {
            // Peek at the group number (always Little Endian for File Meta Information)
            guard let groupNumber = try data.readUInt16LE(at: offset) else {
                if isStrict { throw DICOMError.unexpectedEndOfData }
                break
            }
            
            // Stop when we're past group 0002
            if groupNumber != 0x0002 {
                break
            }
            
            // Parse this element (File Meta Info is always Explicit VR Little Endian)
            let elementOffset = offset
            let element: DataElement
            if isStrict {
                element = try parseExplicitVRElement(byteOrder: .littleEndian)
            } else {
                guard let parsed = try? parseExplicitVRElement(byteOrder: .littleEndian) else { break }
                element = parsed
            }
            try record(element.tag, at: elementOffset, in: &seen)
            if isStrict && element.tag == Tag(group: 0x0002, element: 0x0000) {
                guard element.vr == .UL, element.length == 4, let length = (capture == nil ? element.uint32Value : try data.readUInt32LE(at: offset - 4)) else {
                    throw StrictParsingError.malformedStructure(offset: elementOffset, reason: "Invalid file-meta group length")
                }
                declaredMetaEnd = try valueEndOffset(length: length)
                try requireBoundary(declaredMetaEnd!)
            }
            if capture == nil { elements.append(element) }
        }
        
        if isStrict, let end = declaredMetaEnd, offset != end {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "File-meta group length mismatch")
        }
        return capture == nil ? DataSet(elements: elements) : DataSet()
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
        capture?.currentScope = 1
        
        if isStrict {
            // Compressed syntax is opt-in, within the finite policy validated at entry.
            let allowed = options.allowedTransferSyntaxUIDs ?? ParsingOptions.strictNativeTransferSyntaxUIDs
            guard allowed.contains(transferSyntaxUID) else {
                throw StrictParsingError.unsupportedTransferSyntax(transferSyntaxUID)
            }
        }
        if let allowed = options.allowedTransferSyntaxUIDs, !allowed.contains(transferSyntaxUID) {
            throw DICOMError.unsupportedTransferSyntax(transferSyntaxUID)
        }
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
        var seen = Set<Tag>()
        
        // Parse elements until we reach the end or pixel data
        while offset < data.count {
            // Check max elements limit
            if let maxElements = options.maxElements, elementCount >= maxElements {
                if isStrict { throw StrictParsingError.elementLimitExceeded(maxElements) }
                break
            }
            
            // Check for pixel data (7FE0,0010)
            guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
                if isStrict { throw DICOMError.unexpectedEndOfData }
                break
            }
            guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                if isStrict { throw DICOMError.unexpectedEndOfData }
                break
            }
            
            let currentTag = Tag(group: groupNumber, element: elementNumber)
            if isStrict && groupNumber == 0x0002 {
                throw StrictParsingError.malformedStructure(offset: offset, reason: "File-meta element within main dataset")
            }
            // The low-level reader reserves the element itself. Check here too,
            // before growing the root duplicate-tag set.
            if isStrict && totalElements >= options.strictResourceLimits.maximumTotalElements {
                throw StrictParsingError.resourceLimitExceeded(
                    resource: .totalElements, limit: options.strictResourceLimits.maximumTotalElements)
            }
            try record(currentTag, at: offset, in: &seen)
            
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
                if capture == nil { elements.append(element) }
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
                    if capture == nil { elements.append(pixelDataElement) }
                    break
                    
                case .full:
                    // Parse pixel data element fully
                    let pixelDataElement: DataElement
                    if isEncapsulated {
                        // Dedicated maintained envelope parsing bypasses the ordinary
                        // element readers; charge this root element exactly once here.
                        try reserveElement()
                        try countElement()
                        pixelDataElement = try parseEncapsulatedPixelData(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
                    } else {
                        if isExplicitVR {
                            if isStrict {
                                pixelDataElement = try parseExplicitVRElement(byteOrder: byteOrder)
                            } else {
                                guard let parsed = try? parseExplicitVRElement(byteOrder: byteOrder) else { break }
                                pixelDataElement = parsed
                            }
                        } else {
                            if isStrict {
                                pixelDataElement = try parseImplicitVRElement(byteOrder: byteOrder)
                            } else {
                                guard let parsed = try? parseImplicitVRElement(byteOrder: byteOrder) else { break }
                                pixelDataElement = parsed
                            }
                        }
                    }
                    if capture == nil { elements.append(pixelDataElement) }
                    break
                }
                
                if isStrict {
                    elementCount += 1
                    continue // Full strict reads validate and expose every trailing element.
                }
                // Preserve the historical permissive stopping behavior.
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
                    if isStrict { throw error }
                    // Restore offset and try to skip the element
                    offset = savedOffset
                    if try trySkipElement(isExplicitVR: true, byteOrder: byteOrder) {
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
                    if isStrict { throw error }
                    offset = savedOffset
                    if try trySkipElement(isExplicitVR: false, byteOrder: byteOrder) {
                        continue
                    }
                    break
                }
            }
            
            if capture == nil { elements.append(element) }
            elementCount += 1
        }
        
        return capture == nil ? DataSet(elements: elements) : DataSet()
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
        let strict = options.strictEncapsulation
        if strict && (!isExplicitVR || byteOrder != .littleEndian) {
            throw DICOMError.parsingFailed("Encapsulated Pixel Data requires Explicit VR Little Endian")
        }
        // Read Pixel Data tag (7FE0,0010)
        guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
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
            
            let vrByte0 = try data.byte(at: offset)
            let vrByte1 = try data.byte(at: offset + 1)
            offset += 2
            
            guard let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
                  let parsedVR = VR(rawValue: vrString) else {
                if strict { throw DICOMError.parsingFailed("Invalid encapsulated Pixel Data VR") }
                // Default to OB for pixel data if VR is invalid
                vr = .OB
                offset -= 2 // backtrack
                valueLength = 0xFFFFFFFF
                return DataElement(tag: tag, vr: vr, length: valueLength, valueData: Data(), byteOrder: byteOrder)
            }
            vr = parsedVR
            
            if strict {
                guard vr == .OB, offset + 2 <= data.count, try data.byte(at: offset) == 0, try data.byte(at: offset + 1) == 0 else {
                    throw DICOMError.parsingFailed("Encapsulated Pixel Data requires OB and zero reserved bytes")
                }
            }
            // Skip 2 reserved bytes and read 4-byte length
            offset += 2
            guard let length32 = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let length32 = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        }
        
        // For encapsulated pixel data, the length should be undefined (0xFFFFFFFF)
        guard valueLength == 0xFFFFFFFF else {
            if strict { throw DICOMError.parsingFailed("Encapsulated Pixel Data requires undefined length") }
            // Not actually encapsulated, treat as regular pixel data
            try checkElementLength(valueLength, tag: tag)
            guard offset + Int(valueLength) <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }
            let valueData = try data.subdata(in: offset..<offset + Int(valueLength))
            offset += Int(valueLength)
            return DataElement(tag: tag, vr: vr, length: valueLength, valueData: valueData, byteOrder: byteOrder)
        }
        
        // Parse the Basic Offset Table (first item)
        var offsetTable: [UInt32] = []
        var fragments: [Data] = []
        var fragmentCount = 0
        let capturedElement = try capture?.append(tag: tag, vr: vr, length: valueLength,
            byteOrder: byteOrder, range: offset..<offset)
        
        // Read first item (Basic Offset Table)
        guard let botItemTag = try readItemTag(byteOrder: byteOrder) else {
            throw DICOMError.parsingFailed("Expected Item tag for Basic Offset Table")
        }
        
        guard botItemTag == .item else {
            throw DICOMError.parsingFailed("Expected Item tag (FFFE,E000), found \(botItemTag)")
        }
        offset += 4
        
        guard let botLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        guard botLength != 0xffffffff, Int(botLength) <= data.count - offset,
              Int(botLength) <= options.maximumEncapsulatedBytes else {
            throw DICOMError.limitExceeded("Basic Offset Table exceeds input or encapsulated byte budget")
        }
        if strict && botLength % 4 != 0 { throw DICOMError.parsingFailed("Invalid Basic Offset Table length") }
        if strict, Int(botLength) / 4 > (options.maxFragmentCount ?? 65_536) {
            throw DICOMError.limitExceeded("Basic Offset Table exceeds fragment count budget")
        }
        let botStart = offset
        let botCount = Int(botLength) / 4
        if let capturedElement { capture?.setBOT(botStart..<botStart + Int(botLength), for: capturedElement) }
        let botReader = capture.map { DICOMParserInput(source: $0.source) }
        var nextBOTIndex = 0
        var priorBOT: UInt32?
        var boundedBOTValid = true
        var totalBytes = Int(botLength)
        let fragmentStart = offset + Int(botLength)
        var fragmentOffsets = Set<UInt32>()
        var foundDelimiter = false
        // Parse offset table if present
        if botLength > 0 {
            let numOffsets = Int(botLength) / 4
            for _ in 0..<numOffsets {
                guard let offsetValue = try readUInt32(at: offset, byteOrder: .littleEndian) else {
                    throw DICOMError.unexpectedEndOfData
                }
                if capture == nil { offsetTable.append(offsetValue) }
                else {
                    if let priorBOT, offsetValue <= priorBOT { boundedBOTValid = false }
                    if priorBOT == nil && offsetValue != 0 { boundedBOTValid = false }
                    priorBOT = offsetValue
                }
                offset += 4
            }
        }
        
        // Parse fragments until Sequence Delimitation Item
        while offset < data.count {
            guard let itemTag = try readItemTag(byteOrder: byteOrder) else {
                break
            }
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                guard let delimiterLength = try readUInt32(at: offset + 4, byteOrder: byteOrder) else {
                    throw DICOMError.unexpectedEndOfData
                }
                if strict && delimiterLength != 0 {
                    throw DICOMError.parsingFailed("Nonzero Sequence Delimitation Item length")
                }
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Should be an Item tag
            guard itemTag == .item else {
                throw DICOMError.parsingFailed("Expected Item or Sequence Delimitation tag, found \(itemTag)")
            }
            let streamOffset = offset - fragmentStart
            if capture == nil {
                if let value = UInt32(exactly: streamOffset) { fragmentOffsets.insert(value) }
            } else if nextBOTIndex < botCount {
                let next = try botReader?.readUInt32LE(at: botStart + nextBOTIndex * 4)
                if next == UInt32(exactly: streamOffset) { nextBOTIndex += 1 }
                else if let next, Int(next) < streamOffset { boundedBOTValid = false }
            }
            offset += 4

            guard let fragmentLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4

            guard fragmentLength != 0xffffffff,
                  !strict || (fragmentLength >= 2 && fragmentLength % 2 == 0) else {
                throw DICOMError.parsingFailed("Invalid encapsulated fragment length")
            }
            guard Int(fragmentLength) <= options.maximumEncapsulatedBytes - totalBytes else {
                throw DICOMError.limitExceeded("Encapsulated payload exceeds cumulative byte budget")
            }
            totalBytes += Int(fragmentLength)
            try checkElementLength(fragmentLength, tag: tag)
            if let maxFragments = options.maxFragmentCount ?? (strict ? 65_536 : nil),
               fragmentCount >= maxFragments {
                throw DICOMError.limitExceeded(
                    "Encapsulated fragment count exceeds maxFragmentCount (\(maxFragments))")
            }

            guard offset + Int(fragmentLength) <= data.count else {
                throw DICOMError.unexpectedEndOfData
            }

            if let capture, let capturedElement {
                try capture.appendFragment(offset..<offset + Int(fragmentLength),
                    streamOffset: streamOffset, to: capturedElement)
            } else {
                let fragmentData = try data.subdata(in: offset..<offset + Int(fragmentLength))
                fragments.append(fragmentData)
            }
            fragmentCount += 1
            offset += Int(fragmentLength)
        }
        
        if strict {
            let validOffsets = capture == nil
                ? (offsetTable.isEmpty || (offsetTable.first == 0
                    && zip(offsetTable, offsetTable.dropFirst()).allSatisfy({ $0 < $1 })
                    && offsetTable.allSatisfy({ fragmentOffsets.contains($0) })))
                : (boundedBOTValid && nextBOTIndex == botCount)
            guard foundDelimiter, fragmentCount > 0, validOffsets else {
                throw DICOMError.parsingFailed("Incomplete encapsulation or invalid Basic Offset Table offsets")
            }
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
        guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
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
            
            let vrByte0 = try data.byte(at: offset)
            let vrByte1 = try data.byte(at: offset + 1)
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
            guard let length32 = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let length32 = try readUInt32(at: offset, byteOrder: byteOrder) else {
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
                guard let itemTag = try readItemTag(byteOrder: byteOrder) else {
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
                
                guard let fragmentLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
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
    private func readItemTag(byteOrder: ByteOrder) throws -> Tag? {
        guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder),
              let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
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
    private mutating func trySkipElement(isExplicitVR: Bool, byteOrder: ByteOrder) throws -> Bool {
        // Need at least tag (4 bytes) + length field
        guard offset + 8 <= data.count else { return false }

        // Skip the tag (4 bytes)
        offset += 4

        if isExplicitVR {
            // Read VR (2 bytes)
            guard offset + 2 <= data.count else { return false }
            let vrByte0 = try data.byte(at: offset)
            let vrByte1 = try data.byte(at: offset + 1)
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
                guard let length = try readUInt32(at: offset, byteOrder: byteOrder) else { return false }
                offset += 4
                if length == 0xFFFFFFFF { return false } // Can't skip undefined length
                guard offset + Int(length) <= data.count else { return false }
                offset += Int(length)
            } else {
                // Read 2-byte length
                guard let length = try readUInt16(at: offset, byteOrder: byteOrder) else { return false }
                offset += 2
                guard offset + Int(length) <= data.count else { return false }
                offset += Int(length)
            }
        } else {
            // Implicit VR: 4-byte length
            guard let length = try readUInt32(at: offset, byteOrder: byteOrder) else { return false }
            offset += 4
            if length == 0xFFFFFFFF { return false } // Can't skip undefined length
            guard offset + Int(length) <= data.count else { return false }
            offset += Int(length)
        }

        return true
    }
    
    // MARK: - Byte Order Helpers
    
    /// Reads a 16-bit unsigned integer with the specified byte order
    private func readUInt16(at offset: Int, byteOrder: ByteOrder) throws -> UInt16? {
        switch byteOrder {
        case .littleEndian:
            return try data.readUInt16LE(at: offset)
        case .bigEndian:
            return try data.readUInt16BE(at: offset)
        }
    }
    
    /// Reads a 32-bit unsigned integer with the specified byte order
    private func readUInt32(at offset: Int, byteOrder: ByteOrder) throws -> UInt32? {
        switch byteOrder {
        case .littleEndian:
            return try data.readUInt32LE(at: offset)
        case .bigEndian:
            return try data.readUInt32BE(at: offset)
        }
    }
    
    // MARK: - Deflate Decompression
    
    /// Decompresses deflated data starting at the current offset
    ///
    /// The File Meta Information is not deflated, only the Data Set portion.
    /// Reference: PS3.5 Section A.5
    private mutating func decompressDeflatedData() throws {
        // Get the deflated portion (everything from current offset to end)
        let deflatedData = try data.subdata(in: offset..<data.count)

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
        let headerData = try data.subdata(in: 0..<offset)
        data = DICOMParserInput(data: headerData + decompressedData)
    }
    
    /// Header and leaf work finish before recursive descent. Keeping their
    /// temporary storage out of the recursive dispatcher preserves the strict
    /// depth budget on bounded worker stacks in unoptimized builds too.
    private struct ElementHeader {
        let tag: Tag
        let vr: VR
        let valueLength: UInt32
    }

    private mutating func parseImplicitVRElement(byteOrder: ByteOrder) throws -> DataElement {
        let header = try parseImplicitVRHeader(byteOrder: byteOrder)
        if header.vr == .SQ || header.valueLength == 0xFFFFFFFF {
            return try parseSequenceElement(tag: header.tag, vr: header.vr, valueLength: header.valueLength,
                isExplicitVR: false, byteOrder: byteOrder)
        }
        return try parseLeafValue(header, byteOrder: byteOrder)
    }

    private mutating func parseExplicitVRElement(byteOrder: ByteOrder) throws -> DataElement {
        let header = try parseExplicitVRHeader(byteOrder: byteOrder)
        if header.vr == .SQ || header.valueLength == 0xFFFFFFFF {
            return try parseSequenceElement(tag: header.tag, vr: header.vr, valueLength: header.valueLength,
                isExplicitVR: true, byteOrder: byteOrder)
        }
        return try parseLeafValue(header, byteOrder: byteOrder)
    }

    /// Implicit VR header; dictionary semantics and strict checks are unchanged.
    private mutating func parseImplicitVRHeader(byteOrder: ByteOrder) throws -> ElementHeader {
        try reserveElement()
        // Read tag (4 bytes)
        guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        if isStrict && groupNumber == 0xFFFE {
            throw StrictParsingError.malformedStructure(offset: offset - 4, reason: "Unexpected item or delimiter tag")
        }
        
        // Read value length (4 bytes) - Implicit VR always uses 32-bit length
        // Reference: PS3.5 Section 7.1.3
        guard let valueLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        // Look up VR from the dictionary
        // If not found, use UN (Unknown) per PS3.5 Section 6.2.2
        // Canonical dictionary projection has identical first-VR semantics but
        // does not lazily allocate the descriptive dictionary during a parse.
        let vr = DataElementDictionary.primaryValueRepresentation(for: tag) ?? .UN

        try validateLength(valueLength)
        if valueLength == 0xFFFFFFFF && vr != .SQ && isStrict {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Undefined-length non-SQ value is outside strict scope")
        }
        return ElementHeader(tag: tag, vr: vr, valueLength: valueLength)
    }

    /// Explicit VR header; permissive unknown-VR handling remains unchanged.
    private mutating func parseExplicitVRHeader(byteOrder: ByteOrder) throws -> ElementHeader {
        try reserveElement()
        // Read tag (4 bytes)
        guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
            throw DICOMError.unexpectedEndOfData
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        if isStrict && groupNumber == 0xFFFE {
            throw StrictParsingError.malformedStructure(offset: offset - 4, reason: "Unexpected item or delimiter tag")
        }
        
        // Read VR (2 bytes, ASCII characters)
        guard offset + 2 <= data.count else {
            throw DICOMError.unexpectedEndOfData
        }
        
        let vrByte0 = try data.byte(at: offset)
        let vrByte1 = try data.byte(at: offset + 1)
        offset += 2
        
        let vr: VR
        if let vrString = String(bytes: [vrByte0, vrByte1], encoding: .ascii),
           let parsedVR = VR(rawValue: vrString) {
            vr = parsedVR
        } else {
            if isStrict {
                throw DICOMError.invalidVR(String(bytes: [vrByte0, vrByte1], encoding: .ascii) ?? "non-ASCII")
            }
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
            if isStrict {
                guard try readUInt16(at: offset, byteOrder: byteOrder) == 0 else {
                    throw StrictParsingError.malformedStructure(offset: offset, reason: "Nonzero or missing reserved VR bytes")
                }
            }
            offset += 2
            
            guard let length32 = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            valueLength = length32
        } else {
            guard let length16 = try readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 2
            valueLength = UInt32(length16)
        }
        
        try validateLength(valueLength)
        if valueLength == 0xFFFFFFFF && vr != .SQ && isStrict {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Undefined-length non-SQ value is outside strict scope")
        }
        return ElementHeader(tag: tag, vr: vr, valueLength: valueLength)
    }

    private mutating func parseLeafValue(_ header: ElementHeader, byteOrder: ByteOrder) throws -> DataElement {
        try countElement()
        try checkElementLength(header.valueLength, tag: header.tag)
        let endOffset = try valueEndOffset(length: header.valueLength)
        guard endOffset <= data.count else { throw DICOMError.unexpectedEndOfData }
        try reserveValueBytes(Int(header.valueLength))
        let valueData: Data
        if let capture {
            _ = try capture.append(tag: header.tag, vr: header.vr, length: header.valueLength,
                byteOrder: byteOrder, range: offset..<endOffset)
            valueData = Data()
        } else { valueData = try data.subdata(in: offset..<endOffset) }
        offset = endOffset
        return DataElement(tag: header.tag, vr: header.vr, length: header.valueLength,
            valueData: valueData, byteOrder: byteOrder)
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
        if isStrict {
            try Self.reserve(1, used: &sequenceDepth,
                             limit: options.strictResourceLimits.maximumSequenceDepth,
                             resource: .sequenceDepth)
        } else { sequenceDepth += 1 }
        defer { sequenceDepth -= 1 }
        if sequenceDepth > options.maxSequenceDepth {
            throw DICOMError.limitExceeded(
                "Sequence nesting depth exceeds maxSequenceDepth (\(options.maxSequenceDepth))")
        }
        try countElement()
        let startOffset = offset
        let capturedElement = try capture?.append(tag: tag, vr: vr, length: valueLength,
            byteOrder: byteOrder, range: offset..<offset)
        let parentSequence = capture?.currentSequence
        if let capturedElement { capture?.currentSequence = capturedElement }
        defer { if let parentSequence { capture?.currentSequence = parentSequence } }
        var sequenceItems: [SequenceItem] = []
        
        if valueLength == 0xFFFFFFFF {
            // Undefined length sequence - parse until Sequence Delimitation Item
            sequenceItems = try parseUndefinedLengthSequence(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        } else {
            let declaredEnd = try valueEndOffset(length: valueLength)
            let endOffset = isStrict ? declaredEnd : min(declaredEnd, data.count)
            // Strict raw SQ copies remain separately charged before descent.
            try reserveValueBytes(Int(valueLength))
            sequenceItems = try parseExplicitLengthSequence(endOffset: endOffset, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        }
        
        // Undefined raw SQ length is known only after its delimiter. Charge it
        // before making the copy; child values have already been charged separately.
        if valueLength == 0xFFFFFFFF { try reserveValueBytes(offset - startOffset) }
        // Get the raw value data (for completeness). Clamp both bounds: on
        // truncated input the delimiter-skip paths can leave `offset` a few
        // bytes past `data.count`, and an unclamped range would trap.
        let rawEnd = min(offset, data.count)
        let valueData: Data
        if let capture, let capturedElement {
            capture.setRange(startOffset..<rawEnd, for: capturedElement)
            valueData = Data()
        } else {
            valueData = startOffset <= rawEnd ? try data.subdata(in: startOffset..<rawEnd) : Data()
        }
        
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
        try requireBoundary(endOffset)
        var items: [SequenceItem] = []
        
        while offset < endOffset && offset < data.count {
            // Read item tag
            guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
                break
            }
            guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                break
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                if isStrict {
                    throw StrictParsingError.malformedStructure(offset: offset, reason: "Expected sequence item")
                }
                // Not an item tag - we're done with the sequence
                break
            }
            
            offset += 4
            
            // Read item length
            guard let itemLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            
            // Parse item contents
            let item = try parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
            if capture == nil { items.append(item) }
        }
        
        if isStrict && offset != endOffset {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Sequence boundary mismatch")
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
        var foundDelimiter = false
        
        while offset < data.count {
            // Read tag
            guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                try requireDelimiterLength(byteOrder: byteOrder)
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                throw DICOMError.parsingFailed("Expected Item tag (FFFE,E000) in sequence, found \(itemTag)")
            }
            
            offset += 4
            
            // Read item length
            guard let itemLength = try readUInt32(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            offset += 4
            
            // Parse item contents
            let item = try parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
            if capture == nil { items.append(item) }
        }
        
        if isStrict && !foundDelimiter { throw DICOMError.unexpectedEndOfData }
        return items
    }
    
    /// Parses a single sequence item
    ///
    /// Items can have explicit length or undefined length (0xFFFFFFFF).
    /// Undefined length items end with Item Delimitation Item (FFFE,E00D).
    ///
    /// Reference: PS3.5 Section 7.5.2 & 7.5.3
    private mutating func parseSequenceItem(itemLength: UInt32, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> SequenceItem {
        if isStrict {
            try Self.reserve(1, used: &sequenceItems,
                             limit: options.strictResourceLimits.maximumSequenceItems,
                             resource: .sequenceItems)
        }
        let parentScope = try capture?.beginItem()
        defer { if let parentScope { capture?.currentScope = parentScope } }
        var elements: [DataElement] = []
        
        if itemLength == 0xFFFFFFFF {
            // Undefined length item - parse until Item Delimitation Item
            elements = try parseUndefinedLengthItem(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        } else {
            let declaredEnd = try valueEndOffset(length: itemLength)
            let itemEndOffset = isStrict ? declaredEnd : min(declaredEnd, data.count)
            elements = try parseExplicitLengthItem(endOffset: itemEndOffset, isExplicitVR: isExplicitVR, byteOrder: byteOrder)
        }
        
        return capture == nil ? SequenceItem(elements: elements) : SequenceItem()
    }
    
    /// Parses an item with explicit length
    private mutating func parseExplicitLengthItem(endOffset: Int, isExplicitVR: Bool, byteOrder: ByteOrder) throws -> [DataElement] {
        try requireBoundary(endOffset)
        var elements: [DataElement] = []
        var seen = Set<Tag>()
        
        while offset < endOffset && offset < data.count {
            if try isStrict && readUInt16(at: offset, byteOrder: byteOrder) == 0x0002 {
                throw StrictParsingError.malformedStructure(offset: offset, reason: "File-meta element within sequence item")
            }
            let elementOffset = offset
            let element: DataElement
            if isExplicitVR {
                element = try parseExplicitVRElement(byteOrder: byteOrder)
            } else {
                element = try parseImplicitVRElement(byteOrder: byteOrder)
            }
            try record(element.tag, at: elementOffset, in: &seen)
            if capture == nil { elements.append(element) }
        }
        
        if isStrict && offset != endOffset {
            throw StrictParsingError.malformedStructure(offset: offset, reason: "Item boundary mismatch")
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
        var seen = Set<Tag>()
        var foundDelimiter = false
        
        while offset < data.count {
            // Peek at tag
            guard let groupNumber = try readUInt16(at: offset, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            guard let elementNumber = try readUInt16(at: offset + 2, byteOrder: byteOrder) else {
                throw DICOMError.unexpectedEndOfData
            }
            
            let nextTag = Tag(group: groupNumber, element: elementNumber)
            if isStrict && groupNumber == 0x0002 {
                throw StrictParsingError.malformedStructure(offset: offset, reason: "File-meta element within sequence item")
            }
            
            // Check for Item Delimitation Item
            if nextTag == .itemDelimitationItem {
                try requireDelimiterLength(byteOrder: byteOrder)
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Parse the element
            let elementOffset = offset
            let element: DataElement
            if isExplicitVR {
                element = try parseExplicitVRElement(byteOrder: byteOrder)
            } else {
                element = try parseImplicitVRElement(byteOrder: byteOrder)
            }
            try record(element.tag, at: elementOffset, in: &seen)
            if capture == nil { elements.append(element) }
        }
        
        if isStrict && !foundDelimiter { throw DICOMError.unexpectedEndOfData }
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
