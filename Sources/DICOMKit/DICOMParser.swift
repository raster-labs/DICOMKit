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
struct DICOMParser: ~Copyable {
    private var data: DICOMParserInput
    private var offset: Int
    private let options: BoundedParsingOptions
    private let legacyAllowedTransferSyntaxUIDs: Set<String>?
    private let capture: BoundedParseCapture?
    private var isStrict: Bool { options.validationPolicy == .strict }
    private var totalElements = 0
    private var sequenceDepth = 0
    private var sequenceItems = 0
    private var materializedValueBytes = 0

    /// Subtraction before addition prevents counter overflow even with Int.max limits.
    private static func reserve(_ count: Int, used: inout Int, limit: Int,
                                resource: StrictParsingError.Resource) -> DICOMParserOutcome<Void> {
        guard count >= 0, used >= 0, used <= limit, count <= limit - used else {
            return .failure(DICOMParserFailure.strict(.resourceLimitExceeded(resource: resource, limit: limit)))
        }
        used += count
        return .success(())
    }

    private mutating func reserveElement() -> DICOMParserOutcome<Void> {
        if case .failure(let failure) = data.checkpoint() { return .failure(failure) }
        if isStrict {
            if case .failure(let failure) = Self.reserve(1, used: &totalElements,
                             limit: options.strictResourceLimits.maximumTotalElements,
                             resource: .totalElements) { return .failure(failure) }
        }
        return .success(())
    }

    private mutating func reserveValueBytes(_ count: Int) -> DICOMParserOutcome<Void> {
        if isStrict {
            if case .failure(let failure) = Self.reserve(count, used: &materializedValueBytes,
                             limit: options.strictResourceLimits.maximumMaterializedValueBytes,
                             resource: .materializedValueBytes) { return .failure(failure) }
        }
        return .success(())
    }

    private func valueEndOffset(length: UInt32) -> DICOMParserOutcome<Int> {
        if isStrict {
            guard offset >= 0, offset <= data.count, Int(length) <= data.count - offset else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
        }
        return .success(offset + Int(length))
    }

    private func record(_ tag: Tag, at elementOffset: Int, in seen: inout Set<Tag>) -> DICOMParserOutcome<Void> {
        if isStrict, let capture {
            if case .failure(let failure) = capture.record(tag, at: elementOffset) {
                return .failure(failure)
            }
            return .success(())
        }
        if isStrict && !seen.insert(tag).inserted {
            return .failure(DICOMParserFailure.strict(.duplicateTag(tag: tag, offset: elementOffset)))
        }
        return .success(())
    }

    private func requireBoundary(_ endOffset: Int) -> DICOMParserOutcome<Void> {
        if isStrict && (endOffset < offset || endOffset > data.count) {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .scopeBoundary))
        }
        return .success(())
    }

    private mutating func requireDelimiterLength(byteOrder: ByteOrder) -> DICOMParserOutcome<Void> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if isStrict {
            guard let parsedValue1 = readUInt32(at: offset + 4, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length = parsedValue1 else {
                return .failure(DICOMParserFailure.malformed(offset: offset, reason: .delimiterLength))
            }
            guard length == 0 else {
                return .failure(DICOMParserFailure.malformed(offset: offset, reason: .delimiterLength))
            }
        }
        return .success(())
    }

    private func validateLength(_ length: UInt32) -> DICOMParserOutcome<Void> {
        if isStrict && length != 0xFFFFFFFF && length % 2 != 0 {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .oddValueLength))
        }
        return .success(())
    }

    /// Maintained general element limit, independent of the strict-policy cap.
    private var totalElementCount: Int = 0
    init(data: Data, options: ParsingOptions = .default) {
        self.data = DICOMParserInput(data: data)
        self.offset = 0
        self.options = BoundedParsingOptions(legacy: options)
        legacyAllowedTransferSyntaxUIDs = options.allowedTransferSyntaxUIDs
        self.capture = nil
    }

    init(source: VerifiedSourceView, options: BoundedParsingOptions, capture: BoundedParseCapture) {
        self.data = DICOMParserInput(source: source)
        self.offset = 0
        self.options = options
        legacyAllowedTransferSyntaxUIDs = nil
        self.capture = capture
    }

    // MARK: - Resource Limits

    /// Counts one parsed element against the total-element budget.
    private mutating func countElement() -> DICOMParserOutcome<Void> {
        totalElementCount += 1
        if let maxTotal = options.maxTotalElements, totalElementCount > maxTotal {
            return .failure(DICOMParserFailure.totalElementLimit(maxTotal))
        }
        return .success(())
    }

    /// Validates a defined value length against the per-element ceiling.
    private func checkElementLength(_ length: UInt32, tag: Tag) -> DICOMParserOutcome<Void> {
        if let maxLength = options.maxElementLength, Int(length) > maxLength {
            return .failure(DICOMParserFailure.elementLength(tag: tag, length: length, limit: maxLength))
        }
        return .success(())
    }
    
    /// Parses File Meta Information elements
    ///
    /// File Meta Information elements are always encoded with Explicit VR Little Endian,
    /// regardless of the transfer syntax used for the main data set.
    /// Reference: PS3.10 Section 7.1
    mutating func parseFileMetaInformation(startOffset: Int) throws -> DataSet {
        do { return try parseFileMetaInformationCore(startOffset: startOffset).get() }
        catch { throw error.legacyError }
    }

    mutating func parseFileMetaInformationCore(startOffset: Int) -> DICOMDataSetOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        offset = startOffset
        var elements: [DataElement] = []
        var seen = Set<Tag>()
        var declaredMetaEnd: Int?
        
        // File Meta Information starts after DICM prefix (offset 132)
        // Group 0002 elements only
        while offset < data.count {
            // Peek at the group number (always Little Endian for File Meta Information)
            guard let parsedValue1 = data.readUInt16LE(at: offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let groupNumber = parsedValue1 else {
                if isStrict { return .failure(DICOMParserFailure.unexpectedEndOfData)}
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
                guard let parsedValue2 = parseExplicitVRElement(byteOrder: .littleEndian)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                element = parsedValue2
            } else {
                let parsedValue3 = parseExplicitVRElement(byteOrder: .littleEndian).takeValue(failure: &parsingFailure)
                guard let parsed = parsedValue3 else { break }
                element = parsed
            }
            if case .failure(let failure) = record(element.tag, at: elementOffset, in: &seen) {
                return .failure(failure)
            }
            if isStrict && element.tag == Tag(group: 0x0002, element: 0x0000) {
                guard element.vr == .UL, element.length == 4 else {
                    return .failure(DICOMParserFailure.malformed(offset: elementOffset, reason: .fileMetaLength))
                }
                let metaLength: UInt32?
                if capture == nil { metaLength = element.uint32Value }
                else {
                    guard let value = data.readUInt32LE(at: offset - 4).takeValue(failure: &parsingFailure) else {
                        return .failure(parsingFailure)
                    }
                    metaLength = value
                }
                guard let length = metaLength else {
                    return .failure(DICOMParserFailure.malformed(offset: elementOffset, reason: .fileMetaLength))
                }
                guard let parsedValue5 = valueEndOffset(length: length).takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                declaredMetaEnd = parsedValue5
                if case .failure(let failure) = requireBoundary(declaredMetaEnd!) { return .failure(failure) }
            }
            if capture == nil { elements.append(element) }
        }
        
        if isStrict, let end = declaredMetaEnd, offset != end {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .fileMetaBoundary))
        }
        return .success(capture == nil ? DataSet(elements: elements) : DataSet())
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
            let allowed = legacyAllowedTransferSyntaxUIDs ?? ParsingOptions.strictNativeTransferSyntaxUIDs
            guard allowed.contains(transferSyntaxUID) else {
                throw StrictParsingError.unsupportedTransferSyntax(transferSyntaxUID)
            }
        }
        if let allowed = legacyAllowedTransferSyntaxUIDs, !allowed.contains(transferSyntaxUID) {
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
        
        do { return try parseDataSetGrammar(isExplicitVR: transferSyntax.isExplicitVR,
            byteOrder: transferSyntax.byteOrder, isEncapsulated: transferSyntax.isEncapsulated).get() }
        catch { throw error.legacyError }
    }

    mutating func parseDataSetCore(transferSyntax: BoundedTransferSyntax) -> DICOMDataSetOutcome {
        return parseDataSetCore(startOffset: offset, transferSyntax: transferSyntax)
    }

    mutating func parseDataSetCore(startOffset: Int, transferSyntax: BoundedTransferSyntax)
        -> DICOMDataSetOutcome {
        offset = startOffset
        capture?.currentScope = 1
        guard options.allows(transferSyntax) else {
            return .failure(DICOMParserFailure.managed(DICOMManagedFailure(.invalidTransferSyntax)))
        }
        return parseDataSetGrammar(isExplicitVR: transferSyntax.isExplicitVR,
            byteOrder: .littleEndian, isEncapsulated: transferSyntax.isEncapsulated)
    }

    private mutating func parseDataSetGrammar(isExplicitVR: Bool, byteOrder: ByteOrder,
                                              isEncapsulated: Bool) -> DICOMDataSetOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        var elements: [DataElement] = []
        var elementCount = 0
        var seen = Set<Tag>()
        
        // Parse elements until we reach the end or pixel data
        dataSetElements: while offset < data.count {
            // Check max elements limit
            if let maxElements = options.maxElements, elementCount >= maxElements {
                if isStrict { return .failure(DICOMParserFailure.strict(.elementLimitExceeded(maxElements)))}
                break
            }
            
            // Check for pixel data (7FE0,0010)
            guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let groupNumber = parsedValue1 else {
                if isStrict { return .failure(DICOMParserFailure.unexpectedEndOfData)}
                break
            }
            guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let elementNumber = parsedValue2 else {
                if isStrict { return .failure(DICOMParserFailure.unexpectedEndOfData)}
                break
            }
            
            let currentTag = Tag(group: groupNumber, element: elementNumber)
            if isStrict && groupNumber == 0x0002 {
                return .failure(DICOMParserFailure.malformed(offset: offset, reason: .fileMetaInDataSet))
            }
            // The low-level reader reserves the element itself. Check here too,
            // before growing the root duplicate-tag set.
            if isStrict && totalElements >= options.strictResourceLimits.maximumTotalElements {
                return .failure(DICOMParserFailure.strict(.resourceLimitExceeded(
                    resource: .totalElements, limit: options.strictResourceLimits.maximumTotalElements)))
            }
            if case .failure(let failure) = record(currentTag, at: offset, in: &seen) { return .failure(failure) }
            
            // Check stopAfterTag option
            if let stopTag = options.stopAfterTag, currentTag == stopTag {
                // Parse this element and stop
                let element: DataElement
                if isExplicitVR {
                    let parsedValue3 = parseExplicitVRElement(byteOrder: byteOrder).takeValue(failure: &parsingFailure)
                    guard let parsed = parsedValue3 else {
                        break
                    }
                    element = parsed
                } else {
                    let parsedValue4 = parseImplicitVRElement(byteOrder: byteOrder).takeValue(failure: &parsingFailure)
                    guard let parsed = parsedValue4 else {
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
                    guard let parsedValue5 = parsePixelDataMetadataOnly(
                        isExplicitVR: isExplicitVR,
                        byteOrder: byteOrder,
                        isEncapsulated: isEncapsulated
                    ).takeValue(failure: &parsingFailure) else { return .failure(parsingFailure) }
                    let pixelDataElement = parsedValue5
                    if capture == nil { elements.append(pixelDataElement) }
                    break
                    
                case .full:
                    // Parse pixel data element fully
                    let pixelDataElement: DataElement
                    if isEncapsulated {
                        // Dedicated maintained envelope parsing bypasses the ordinary
                        // element readers; charge this root element exactly once here.
                        if case .failure(let failure) = reserveElement() { return .failure(failure) }
                        if case .failure(let failure) = countElement() { return .failure(failure) }
                        guard let parsedValue6 = parseEncapsulatedPixelData(isExplicitVR: isExplicitVR,
                            byteOrder: byteOrder)
                            .takeValue(failure: &parsingFailure) else {
                            return .failure(parsingFailure)
                        }
                        pixelDataElement = parsedValue6
                    } else {
                        if isExplicitVR {
                            if isStrict {
                                guard let parsedValue7 = parseExplicitVRElement(byteOrder: byteOrder)
                                    .takeValue(failure: &parsingFailure) else {
                                    return .failure(parsingFailure)
                                }
                                pixelDataElement = parsedValue7
                            } else {
                                let parsedValue8 = parseExplicitVRElement(byteOrder: byteOrder)
                                    .takeValue(failure: &parsingFailure)
                                guard let parsed = parsedValue8 else { break }
                                pixelDataElement = parsed
                            }
                        } else {
                            if isStrict {
                                guard let parsedValue9 = parseImplicitVRElement(byteOrder: byteOrder)
                                    .takeValue(failure: &parsingFailure) else {
                                    return .failure(parsingFailure)
                                }
                                pixelDataElement = parsedValue9
                            } else {
                                let parsedValue10 = parseImplicitVRElement(byteOrder: byteOrder)
                                    .takeValue(failure: &parsingFailure)
                                guard let parsed = parsedValue10 else { break }
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
                switch parseExplicitVRElement(byteOrder: byteOrder) {
                case .success(let parsed): element = parsed
                case .failure(let error):
                    if isStrict || error.isLegacyLimit { return .failure(error) }
                    // Restore offset and try to skip the element
                    offset = savedOffset
                    guard let parsedValue11 = trySkipElement(isExplicitVR: true, byteOrder: byteOrder)
                        .takeValue(failure: &parsingFailure) else {
                        return .failure(parsingFailure)
                    }
                    if parsedValue11 {
                        continue
                    }
                    break dataSetElements
                }
            } else {
                switch parseImplicitVRElement(byteOrder: byteOrder) {
                case .success(let parsed): element = parsed
                case .failure(let error):
                    if isStrict || error.isLegacyLimit { return .failure(error) }
                    offset = savedOffset
                    guard let parsedValue12 = trySkipElement(isExplicitVR: false, byteOrder: byteOrder)
                        .takeValue(failure: &parsingFailure) else {
                        return .failure(parsingFailure)
                    }
                    if parsedValue12 {
                        continue
                    }
                    break dataSetElements
                }
            }
            
            if capture == nil { elements.append(element) }
            elementCount += 1
        }
        
        return .success(capture == nil ? DataSet(elements: elements) : DataSet())
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
    private mutating func parseEncapsulatedPixelData(isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        let strict = options.strictEncapsulation
        if strict && (!isExplicitVR || byteOrder != .littleEndian) {
            return .failure(DICOMParserFailure.parsing(.encapsulatedSyntax))
        }
        // Read Pixel Data tag (7FE0,0010)
        guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let groupNumber = parsedValue1 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let elementNumber = parsedValue2 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read VR and length
        let vr: VR
        let valueLength: UInt32
        
        if isExplicitVR {
            guard offset + 2 <= data.count else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            
            guard let parsedValue3 = data.byte(at: offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte0 = parsedValue3
            guard let parsedValue4 = data.byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte1 = parsedValue4
            offset += 2
            
            guard let parsedVR = VR.fromEncodedBytes(vrByte0, vrByte1) else {
                if strict { return .failure(DICOMParserFailure.parsing(.encapsulatedVR))}
                // Default to OB for pixel data if VR is invalid
                vr = .OB
                offset -= 2 // backtrack
                valueLength = 0xFFFFFFFF
                return .success(DataElement(tag: tag, vr: vr, length: valueLength, valueData: Data(),
                    byteOrder: byteOrder))
            }
            vr = parsedVR
            
            if strict {
                guard vr == .OB else {
                    return .failure(DICOMParserFailure.parsing(.encapsulatedReserved))
                }
                guard offset + 2 <= data.count else {
                    return .failure(DICOMParserFailure.parsing(.encapsulatedReserved))
                }
                guard let parsedValue5 = data.byte(at: offset).takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard parsedValue5 == 0 else {
                    return .failure(DICOMParserFailure.parsing(.encapsulatedReserved))
                }
                guard let parsedValue6 = data.byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard parsedValue6 == 0 else {
                    return .failure(DICOMParserFailure.parsing(.encapsulatedReserved))
                }
            }
            // Skip 2 reserved bytes and read 4-byte length
            offset += 2
            guard let parsedValue7 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length32 = parsedValue7 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let parsedValue8 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length32 = parsedValue8 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            valueLength = length32
        }
        
        // For encapsulated pixel data, the length should be undefined (0xFFFFFFFF)
        guard valueLength == 0xFFFFFFFF else {
            if strict { return .failure(DICOMParserFailure.parsing(.encapsulatedLength))}
            // Not actually encapsulated, treat as regular pixel data
            if case .failure(let failure) = checkElementLength(valueLength, tag: tag) { return .failure(failure) }
            guard offset + Int(valueLength) <= data.count else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            guard let parsedValue9 = data.subdata(in: offset..<offset + Int(valueLength))
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let valueData = parsedValue9
            offset += Int(valueLength)
            return .success(DataElement(tag: tag, vr: vr, length: valueLength, valueData: valueData,
                byteOrder: byteOrder))
        }
        
        // Parse the Basic Offset Table (first item)
        var offsetTable: [UInt32] = []
        var fragments: [Data] = []
        var fragmentCount = 0
        let capturedElement: Int?
        if let capture {
            guard let parsedValue10 = capture.append(tag: tag, vr: vr, length: valueLength,
                byteOrder: byteOrder, range: offset..<offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            capturedElement = parsedValue10
        } else { capturedElement = nil }
        
        // Read first item (Basic Offset Table)
        guard let parsedValue11 = readItemTag(byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let botItemTag = parsedValue11 else {
            return .failure(DICOMParserFailure.parsing(.missingBOTItem))
        }
        
        guard botItemTag == .item else {
            return .failure(DICOMParserFailure.expectedBOTItem(botItemTag))
        }
        offset += 4
        
        guard let parsedValue12 = readUInt32(at: offset, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let botLength = parsedValue12 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        guard botLength != 0xffffffff, Int(botLength) <= data.count - offset,
              Int(botLength) <= options.maximumEncapsulatedBytes else {
            return .failure(DICOMParserFailure.limit(.botBytes))
        }
        if strict && botLength % 4 != 0 { return .failure(DICOMParserFailure.parsing(.botLength))}
        if strict, Int(botLength) / 4 > (options.maxFragmentCount ?? 65_536) {
            return .failure(DICOMParserFailure.limit(.botCount))
        }
        let botStart = offset
        let botCount = Int(botLength) / 4
        if let capturedElement { capture?.setBOT(botStart..<botStart + Int(botLength), for: capturedElement) }
        var botReader: DICOMParserInput?
        if let capture { botReader = DICOMParserInput(source: capture.source) }
        else { botReader = nil }
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
                guard let parsedValue13 = readUInt32(at: offset, byteOrder: .littleEndian)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let offsetValue = parsedValue13 else {
                    return .failure(DICOMParserFailure.unexpectedEndOfData)
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
            guard let parsedValue14 = readItemTag(byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let itemTag = parsedValue14 else {
                break
            }
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                guard let parsedValue15 = readUInt32(at: offset + 4, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let delimiterLength = parsedValue15 else {
                    return .failure(DICOMParserFailure.unexpectedEndOfData)
                }
                if strict && delimiterLength != 0 {
                    return .failure(DICOMParserFailure.parsing(.sequenceDelimiterLength))
                }
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Should be an Item tag
            guard itemTag == .item else {
                return .failure(DICOMParserFailure.expectedItemOrDelimiter(itemTag))
            }
            let streamOffset = offset - fragmentStart
            if capture == nil {
                if let value = UInt32(exactly: streamOffset) { fragmentOffsets.insert(value) }
            } else if nextBOTIndex < botCount {
                guard let parsedValue16 = (botReader?.readUInt32LE(at: botStart + nextBOTIndex * 4) ?? .success(nil))
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                let next = parsedValue16
                if next == UInt32(exactly: streamOffset) { nextBOTIndex += 1 }
                else if let next, Int(next) < streamOffset { boundedBOTValid = false }
            }
            offset += 4

            guard let parsedValue17 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let fragmentLength = parsedValue17 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4

            guard fragmentLength != 0xffffffff,
                  !strict || (fragmentLength >= 2 && fragmentLength % 2 == 0) else {
                return .failure(DICOMParserFailure.parsing(.fragmentLength))
            }
            guard Int(fragmentLength) <= options.maximumEncapsulatedBytes - totalBytes else {
                return .failure(DICOMParserFailure.limit(.encapsulatedBytes))
            }
            totalBytes += Int(fragmentLength)
            if case .failure(let failure) = checkElementLength(fragmentLength, tag: tag) { return .failure(failure) }
            if let maxFragments = options.maxFragmentCount ?? (strict ? 65_536 : nil),
               fragmentCount >= maxFragments {
                return .failure(DICOMParserFailure.fragmentCountLimit(maxFragments))
            }

            guard offset + Int(fragmentLength) <= data.count else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }

            if let capture, let capturedElement {
                if case .failure(let failure) = capture.appendFragment(offset..<offset + Int(fragmentLength),
                    streamOffset: streamOffset, to: capturedElement) { return .failure(failure) }
            } else {
                guard let parsedValue18 = data.subdata(in: offset..<offset + Int(fragmentLength))
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                let fragmentData = parsedValue18
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
                return .failure(DICOMParserFailure.parsing(.incompleteEncapsulation))
            }
        }
        return .success(DataElement(
            tag: tag,
            vr: vr,
            length: valueLength,
            valueData: Data(),
            encapsulatedFragments: fragments,
            encapsulatedOffsetTable: offsetTable,
            byteOrder: byteOrder
        ))
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
    ) -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        // Read tag (should be 7FE0,0010)
        guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let groupNumber = parsedValue1 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let elementNumber = parsedValue2 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        
        // Read VR and length
        let vr: VR
        let valueLength: UInt32
        
        if isExplicitVR {
            guard offset + 2 <= data.count else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            
            guard let parsedValue3 = data.byte(at: offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte0 = parsedValue3
            guard let parsedValue4 = data.byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte1 = parsedValue4
            offset += 2
            
            guard let parsedVR = VR.fromEncodedBytes(vrByte0, vrByte1) else {
                // Default to OB for pixel data if VR is invalid
                vr = .OB
                offset -= 2 // backtrack
                valueLength = 0
                return .success(DataElement(tag: tag, vr: vr, length: 0, valueData: Data(), byteOrder: byteOrder))
            }
            vr = parsedVR
            
            // Skip 2 reserved bytes and read 4-byte length
            offset += 2
            guard let parsedValue5 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length32 = parsedValue5 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            valueLength = length32
        } else {
            // Implicit VR - use OW for pixel data
            vr = .OW
            guard let parsedValue6 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length32 = parsedValue6 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
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
                guard let parsedValue7 = readItemTag(byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let itemTag = parsedValue7 else {
                    break
                }
                
                if itemTag == .sequenceDelimitationItem {
                    offset += 4 // Skip tag
                    offset += 4 // Skip length
                    break
                }
                
                guard itemTag == .item else {
                    return .failure(DICOMParserFailure.parsing(.expectedItemOrDelimiter))
                }
                offset += 4
                
                guard let parsedValue8 = readUInt32(at: offset, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let fragmentLength = parsedValue8 else {
                    return .failure(DICOMParserFailure.unexpectedEndOfData)
                }
                offset += 4
                offset += Int(fragmentLength)
            }
        }
        
        // Return element with metadata but no value data
        return .success(DataElement(tag: tag, vr: vr, length: valueLength, valueData: Data(), byteOrder: byteOrder))
    }
    
    /// Reads an Item or Delimiter tag
    private mutating func readItemTag(byteOrder: ByteOrder) -> DICOMParserOutcome<Tag?> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let groupNumber = parsedValue1 else {
            return .success(nil)
        }
        guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let elementNumber = parsedValue2 else {
            return .success(nil)
        }
        return .success(Tag(group: groupNumber, element: elementNumber))
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
    private mutating func trySkipElement(isExplicitVR: Bool, byteOrder: ByteOrder) -> DICOMParserOutcome<Bool> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        // Need at least tag (4 bytes) + length field
        guard offset + 8 <= data.count else { return .success(false) }

        // Skip the tag (4 bytes)
        offset += 4

        if isExplicitVR {
            // Read VR (2 bytes)
            guard offset + 2 <= data.count else { return .success(false) }
            guard let parsedValue1 = data.byte(at: offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte0 = parsedValue1
            guard let parsedValue2 = data.byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let vrByte1 = parsedValue2
            offset += 2

            let vr: VR
            if let parsedVR = VR.fromEncodedBytes(vrByte0, vrByte1) {
                vr = parsedVR
            } else {
                vr = .UN
            }

            if vr.uses32BitLength {
                // Skip 2 reserved bytes + read 4-byte length
                guard offset + 6 <= data.count else { return .success(false) }
                offset += 2
                guard let parsedValue3 = readUInt32(at: offset, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let length = parsedValue3 else { return .success(false) }
                offset += 4
                if length == 0xFFFFFFFF { return .success(false) } // Can't skip undefined length
                guard offset + Int(length) <= data.count else { return .success(false) }
                offset += Int(length)
            } else {
                // Read 2-byte length
                guard let parsedValue4 = readUInt16(at: offset, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard let length = parsedValue4 else { return .success(false) }
                offset += 2
                guard offset + Int(length) <= data.count else { return .success(false) }
                offset += Int(length)
            }
        } else {
            // Implicit VR: 4-byte length
            guard let parsedValue5 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length = parsedValue5 else { return .success(false) }
            offset += 4
            if length == 0xFFFFFFFF { return .success(false) } // Can't skip undefined length
            guard offset + Int(length) <= data.count else { return .success(false) }
            offset += Int(length)
        }

        return .success(true)
    }
    
    // MARK: - Byte Order Helpers
    
    /// Reads a 16-bit unsigned integer with the specified byte order
    private mutating func readUInt16(at offset: Int, byteOrder: ByteOrder) -> DICOMParserOutcome<UInt16?> {
        switch byteOrder {
        case .littleEndian:
            return data.readUInt16LE(at: offset)
        case .bigEndian:
            return data.readUInt16BE(at: offset)
        }
    }
    
    /// Reads a 32-bit unsigned integer with the specified byte order
    private mutating func readUInt32(at offset: Int, byteOrder: ByteOrder) -> DICOMParserOutcome<UInt32?> {
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
        let deflatedData = try data.subdata(in: offset..<data.count).get()

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
        let headerData = try data.subdata(in: 0..<offset).get()
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

    private mutating func parseImplicitVRElement(byteOrder: ByteOrder) -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard let parsedValue1 = parseImplicitVRHeader(byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let header = parsedValue1
        if header.vr == .SQ || header.valueLength == 0xFFFFFFFF {
            return parseSequenceElement(tag: header.tag, vr: header.vr, valueLength: header.valueLength,
                isExplicitVR: false, byteOrder: byteOrder)
        }
        return parseLeafValue(header, byteOrder: byteOrder)
    }

    private mutating func parseExplicitVRElement(byteOrder: ByteOrder) -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        guard let parsedValue1 = parseExplicitVRHeader(byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let header = parsedValue1
        if header.vr == .SQ || header.valueLength == 0xFFFFFFFF {
            return parseSequenceElement(tag: header.tag, vr: header.vr, valueLength: header.valueLength,
                isExplicitVR: true, byteOrder: byteOrder)
        }
        return parseLeafValue(header, byteOrder: byteOrder)
    }

    /// Implicit VR header; dictionary semantics and strict checks are unchanged.
    private mutating func parseImplicitVRHeader(byteOrder: ByteOrder) -> DICOMParserOutcome<ElementHeader> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if case .failure(let failure) = reserveElement() { return .failure(failure) }
        // Read tag (4 bytes)
        guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let groupNumber = parsedValue1 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let elementNumber = parsedValue2 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        if isStrict && groupNumber == 0xFFFE {
            return .failure(DICOMParserFailure.malformed(offset: offset - 4, reason: .unexpectedDelimiter))
        }
        
        // Read value length (4 bytes) - Implicit VR always uses 32-bit length
        // Reference: PS3.5 Section 7.1.3
        guard let parsedValue3 = readUInt32(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let valueLength = parsedValue3 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        // Look up VR from the dictionary
        // If not found, use UN (Unknown) per PS3.5 Section 6.2.2
        // Canonical dictionary projection has identical first-VR semantics but
        // does not lazily allocate the descriptive dictionary during a parse.
        let vr = DataElementDictionary.primaryValueRepresentation(for: tag) ?? .UN

        if case .failure(let failure) = validateLength(valueLength) { return .failure(failure) }
        if valueLength == 0xFFFFFFFF && vr != .SQ && isStrict {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .undefinedNonSequence))
        }
        return .success(ElementHeader(tag: tag, vr: vr, valueLength: valueLength))
    }

    /// Explicit VR header; permissive unknown-VR handling remains unchanged.
    private mutating func parseExplicitVRHeader(byteOrder: ByteOrder) -> DICOMParserOutcome<ElementHeader> {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if case .failure(let failure) = reserveElement() { return .failure(failure) }
        // Read tag (4 bytes)
        guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let groupNumber = parsedValue1 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
            .takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        guard let elementNumber = parsedValue2 else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        offset += 4
        
        let tag = Tag(group: groupNumber, element: elementNumber)
        if isStrict && groupNumber == 0xFFFE {
            return .failure(DICOMParserFailure.malformed(offset: offset - 4, reason: .unexpectedDelimiter))
        }
        
        // Read VR (2 bytes, ASCII characters)
        guard offset + 2 <= data.count else {
            return .failure(DICOMParserFailure.unexpectedEndOfData)
        }
        
        guard let parsedValue3 = data.byte(at: offset).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let vrByte0 = parsedValue3
        guard let parsedValue4 = data.byte(at: offset + 1).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let vrByte1 = parsedValue4
        offset += 2
        
        let vr: VR
        if let parsedVR = VR.fromEncodedBytes(vrByte0, vrByte1) {
            vr = parsedVR
        } else {
            if isStrict {
                return .failure(DICOMParserFailure.invalidVR(vrByte0, vrByte1))
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
                guard let parsedValue5 = readUInt16(at: offset, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                guard parsedValue5 == 0 else {
                    return .failure(DICOMParserFailure.malformed(offset: offset, reason: .reservedVRBytes))
                }
            }
            offset += 2
            
            guard let parsedValue6 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length32 = parsedValue6 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            valueLength = length32
        } else {
            guard let parsedValue7 = readUInt16(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let length16 = parsedValue7 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 2
            valueLength = UInt32(length16)
        }
        
        if case .failure(let failure) = validateLength(valueLength) { return .failure(failure) }
        if valueLength == 0xFFFFFFFF && vr != .SQ && isStrict {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .undefinedNonSequence))
        }
        return .success(ElementHeader(tag: tag, vr: vr, valueLength: valueLength))
    }

    private mutating func parseLeafValue(_ header: ElementHeader, byteOrder: ByteOrder)
        -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if case .failure(let failure) = countElement() { return .failure(failure) }
        if case .failure(let failure) = checkElementLength(header.valueLength, tag: header.tag) {
            return .failure(failure)
        }
        guard let parsedValue1 = valueEndOffset(length: header.valueLength).takeValue(failure: &parsingFailure) else {
            return .failure(parsingFailure)
        }
        let endOffset = parsedValue1
        guard endOffset <= data.count else { return .failure(DICOMParserFailure.unexpectedEndOfData)}
        if case .failure(let failure) = reserveValueBytes(Int(header.valueLength)) { return .failure(failure) }
        let valueData: Data
        if let capture {
            guard let parsedValue2 = capture.append(tag: header.tag, vr: header.vr, length: header.valueLength,
                byteOrder: byteOrder, range: offset..<endOffset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            _ = parsedValue2
            valueData = Data()
        } else {
            guard let value = data.subdata(in: offset..<endOffset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            valueData = value
        }
        offset = endOffset
        return .success(DataElement(tag: header.tag, vr: header.vr, length: header.valueLength,
            valueData: valueData, byteOrder: byteOrder))
    }

    // MARK: - Sequence Parsing
    
    /// Parses a sequence element (SQ VR) and its items
    ///
    /// Sequences can have either explicit length or undefined length (0xFFFFFFFF).
    /// Each item in the sequence is delimited by Item tags (FFFE,E000).
    /// Undefined length sequences end with Sequence Delimitation Item (FFFE,E0DD).
    ///
    /// Reference: PS3.5 Section 7.5 - Nesting of Data Sets
    private mutating func parseSequenceElement(tag: Tag, vr: VR, valueLength: UInt32, isExplicitVR: Bool,
        byteOrder: ByteOrder)
        -> DICOMDataElementOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if isStrict {
            if case .failure(let failure) = Self.reserve(1, used: &sequenceDepth,
                             limit: options.strictResourceLimits.maximumSequenceDepth,
                             resource: .sequenceDepth) { return .failure(failure) }
        } else { sequenceDepth += 1 }
        defer { sequenceDepth -= 1 }
        if sequenceDepth > options.maxSequenceDepth {
            return .failure(DICOMParserFailure.sequenceDepthLimit(options.maxSequenceDepth))
        }
        if case .failure(let failure) = countElement() { return .failure(failure) }
        let startOffset = offset
        let capturedElement: Int?
        if let capture {
            guard let parsedValue1 = capture.append(tag: tag, vr: vr, length: valueLength,
                byteOrder: byteOrder, range: offset..<offset).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            capturedElement = parsedValue1
        } else { capturedElement = nil }
        let parentSequence = capture?.currentSequence
        if let capturedElement { capture?.currentSequence = capturedElement }
        defer { if let parentSequence { capture?.currentSequence = parentSequence } }
        var sequenceItems: [SequenceItem] = []
        
        if valueLength == 0xFFFFFFFF {
            // Undefined length sequence - parse until Sequence Delimitation Item
            guard let parsedValue2 = parseUndefinedLengthSequence(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            sequenceItems = parsedValue2
        } else {
            guard let parsedValue3 = valueEndOffset(length: valueLength).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let declaredEnd = parsedValue3
            let endOffset = isStrict ? declaredEnd : min(declaredEnd, data.count)
            // Strict raw SQ copies remain separately charged before descent.
            if case .failure(let failure) = reserveValueBytes(Int(valueLength)) { return .failure(failure) }
            guard let parsedValue4 = parseExplicitLengthSequence(endOffset: endOffset, isExplicitVR: isExplicitVR,
                byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            sequenceItems = parsedValue4
        }
        
        // Undefined raw SQ length is known only after its delimiter. Charge it
        // before making the copy; child values have already been charged separately.
        if valueLength == 0xFFFFFFFF {
            if case .failure(let failure) = reserveValueBytes(offset - startOffset) {
                return .failure(failure)
            }
        }
        // Get the raw value data (for completeness). Clamp both bounds: on
        // truncated input the delimiter-skip paths can leave `offset` a few
        // bytes past `data.count`, and an unclamped range would trap.
        let rawEnd = min(offset, data.count)
        let valueData: Data
        if let capture, let capturedElement {
            capture.setRange(startOffset..<rawEnd, for: capturedElement)
            valueData = Data()
        } else {
            if startOffset <= rawEnd {
                guard let value = data.subdata(in: startOffset..<rawEnd).takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                valueData = value
            }
            else { valueData = Data() }
        }
        
        return .success(DataElement(
            tag: tag,
            vr: vr,
            length: valueLength,
            valueData: valueData,
            sequenceItems: sequenceItems,
            byteOrder: byteOrder
        ))
    }
    
    /// Parses a sequence with explicit length
    ///
    /// The sequence ends when we reach the specified end offset.
    /// Reference: PS3.5 Section 7.5.2
    private mutating func parseExplicitLengthSequence(endOffset: Int, isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMSequenceItemsOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if case .failure(let failure) = requireBoundary(endOffset) { return .failure(failure) }
        var items: [SequenceItem] = []
        
        while offset < endOffset && offset < data.count {
            // Read item tag
            guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let groupNumber = parsedValue1 else {
                break
            }
            guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let elementNumber = parsedValue2 else {
                break
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                if isStrict {
                    return .failure(DICOMParserFailure.malformed(offset: offset, reason: .expectedSequenceItem))
                }
                // Not an item tag - we're done with the sequence
                break
            }
            
            offset += 4
            
            // Read item length
            guard let parsedValue3 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let itemLength = parsedValue3 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            
            // Parse item contents
            guard let parsedValue4 = parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR,
                byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let item = parsedValue4
            if capture == nil { items.append(item) }
        }
        
        if isStrict && offset != endOffset {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .sequenceBoundary))
        }
        // Ensure we've consumed all the sequence data
        if offset < endOffset {
            offset = endOffset
        }
        
        return .success(items)
    }
    
    /// Parses a sequence with undefined length
    ///
    /// The sequence ends with Sequence Delimitation Item (FFFE,E0DD).
    /// Reference: PS3.5 Section 7.5.1
    private mutating func parseUndefinedLengthSequence(isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMSequenceItemsOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        var items: [SequenceItem] = []
        var foundDelimiter = false
        
        while offset < data.count {
            // Read tag
            guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let groupNumber = parsedValue1 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let elementNumber = parsedValue2 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            
            let itemTag = Tag(group: groupNumber, element: elementNumber)
            
            // Check for Sequence Delimitation Item
            if itemTag == .sequenceDelimitationItem {
                if case .failure(let failure) = requireDelimiterLength(byteOrder: byteOrder) {
                    return .failure(failure)
                }
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Must be Item tag (FFFE,E000)
            guard itemTag == .item else {
                return .failure(DICOMParserFailure.expectedSequenceItem(itemTag))
            }
            
            offset += 4
            
            // Read item length
            guard let parsedValue3 = readUInt32(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let itemLength = parsedValue3 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            offset += 4
            
            // Parse item contents
            guard let parsedValue4 = parseSequenceItem(itemLength: itemLength, isExplicitVR: isExplicitVR,
                byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let item = parsedValue4
            if capture == nil { items.append(item) }
        }
        
        if isStrict && !foundDelimiter { return .failure(DICOMParserFailure.unexpectedEndOfData)}
        return .success(items)
    }
    
    /// Parses a single sequence item
    ///
    /// Items can have explicit length or undefined length (0xFFFFFFFF).
    /// Undefined length items end with Item Delimitation Item (FFFE,E00D).
    ///
    /// Reference: PS3.5 Section 7.5.2 & 7.5.3
    private mutating func parseSequenceItem(itemLength: UInt32, isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMSequenceItemOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if isStrict {
            if case .failure(let failure) = Self.reserve(1, used: &sequenceItems,
                             limit: options.strictResourceLimits.maximumSequenceItems,
                             resource: .sequenceItems) { return .failure(failure) }
        }
        let parentScope: Int?
        if let capture {
            guard let value = capture.beginItem().takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            parentScope = value
        }
        else { parentScope = nil }
        defer { if let parentScope { capture?.currentScope = parentScope } }
        var elements: [DataElement] = []
        
        if itemLength == 0xFFFFFFFF {
            // Undefined length item - parse until Item Delimitation Item
            guard let parsedValue2 = parseUndefinedLengthItem(isExplicitVR: isExplicitVR, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            elements = parsedValue2
        } else {
            guard let parsedValue3 = valueEndOffset(length: itemLength).takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            let declaredEnd = parsedValue3
            let itemEndOffset = isStrict ? declaredEnd : min(declaredEnd, data.count)
            guard let parsedValue4 = parseExplicitLengthItem(endOffset: itemEndOffset, isExplicitVR: isExplicitVR,
                byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            elements = parsedValue4
        }
        
        return .success(capture == nil ? SequenceItem(elements: elements) : SequenceItem())
    }
    
    /// Parses an item with explicit length
    private mutating func parseExplicitLengthItem(endOffset: Int, isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMDataElementsOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        if case .failure(let failure) = requireBoundary(endOffset) { return .failure(failure) }
        var elements: [DataElement] = []
        var seen = Set<Tag>()
        
        while offset < endOffset && offset < data.count {
            if isStrict {
                guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                if parsedValue1 == 0x0002 {
                    return .failure(DICOMParserFailure.malformed(offset: offset, reason: .fileMetaInItem))
                }
            }
            let elementOffset = offset
            let element: DataElement
            if isExplicitVR {
                guard let parsedValue2 = parseExplicitVRElement(byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                element = parsedValue2
            } else {
                guard let parsedValue3 = parseImplicitVRElement(byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                element = parsedValue3
            }
            if case .failure(let failure) = record(element.tag, at: elementOffset, in: &seen) {
                return .failure(failure)
            }
            if capture == nil { elements.append(element) }
        }
        
        if isStrict && offset != endOffset {
            return .failure(DICOMParserFailure.malformed(offset: offset, reason: .itemBoundary))
        }
        // Ensure we've consumed all the item data
        if offset < endOffset {
            offset = endOffset
        }
        
        return .success(elements)
    }
    
    /// Parses an item with undefined length
    ///
    /// Ends with Item Delimitation Item (FFFE,E00D).
    private mutating func parseUndefinedLengthItem(isExplicitVR: Bool, byteOrder: ByteOrder)
        -> DICOMDataElementsOutcome {
        var parsingFailure: DICOMParserFailure = .unexpectedEndOfData
        var elements: [DataElement] = []
        var seen = Set<Tag>()
        var foundDelimiter = false
        
        while offset < data.count {
            // Peek at tag
            guard let parsedValue1 = readUInt16(at: offset, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let groupNumber = parsedValue1 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            guard let parsedValue2 = readUInt16(at: offset + 2, byteOrder: byteOrder)
                .takeValue(failure: &parsingFailure) else {
                return .failure(parsingFailure)
            }
            guard let elementNumber = parsedValue2 else {
                return .failure(DICOMParserFailure.unexpectedEndOfData)
            }
            
            let nextTag = Tag(group: groupNumber, element: elementNumber)
            if isStrict && groupNumber == 0x0002 {
                return .failure(DICOMParserFailure.malformed(offset: offset, reason: .fileMetaInItem))
            }
            
            // Check for Item Delimitation Item
            if nextTag == .itemDelimitationItem {
                if case .failure(let failure) = requireDelimiterLength(byteOrder: byteOrder) {
                    return .failure(failure)
                }
                offset += 8
                foundDelimiter = true
                break
            }
            
            // Parse the element
            let elementOffset = offset
            let element: DataElement
            if isExplicitVR {
                guard let parsedValue3 = parseExplicitVRElement(byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                element = parsedValue3
            } else {
                guard let parsedValue4 = parseImplicitVRElement(byteOrder: byteOrder)
                    .takeValue(failure: &parsingFailure) else {
                    return .failure(parsingFailure)
                }
                element = parsedValue4
            }
            if case .failure(let failure) = record(element.tag, at: elementOffset, in: &seen) {
                return .failure(failure)
            }
            if capture == nil { elements.append(element) }
        }
        
        if isStrict && !foundDelimiter { return .failure(DICOMParserFailure.unexpectedEndOfData)}
        return .success(elements)
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
