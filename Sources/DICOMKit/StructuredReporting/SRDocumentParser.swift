// NEMA-verified: 2026a, checked 2026-09-30 — SR Document Series / General Module attributes per PS3.3 2026a Tables C.17-1 and C.17-2 (incl. Verifying Observer Sequence (0040,A073) Items); Code Sequence Macro reading (one of Code Value / Long Code Value / URN Code Value, Coding Scheme Designator 1C) per Table 8.8-1a; TABLE cells per Table C.18.10-1; SCOORD3D (3006,0024) per Table C.18.9-1; content module tags per PS3.6 Table 6-1; the NUM qualifier gap is recorded; Content Sequence (0040,A730) read under every value type per Table C.17-6 (D31)
// NEMA-verified: 2026a, checked 2026-10-01 — NUM: an empty Measured Value Sequence (Type 2, zero or one Item, PS3.3 2026a Table C.18.1-1 / C.18.1) stays without a value (D194) and Numeric Value Qualifier Code Sequence (0040,A301) is read against CID 42 = CID 43 + CID 44, 12 codes compared (D195); Referenced Waveform Channels (0040,A0B0) read as (M,C) pairs per C.18.5.1.1 (D196); Type 2 Patient's Birth Date / Sex (Table C.7-1), Referring Physician's Name / Study ID (Table C.7-3) and Manufacturer (Table C.7-8) read, zero length as unknown (D198)
/// DICOM Structured Reporting Document Parser
///
/// Parses DICOM SR data sets into the content item tree model.
///
/// Reference: PS3.3 Section C.17 - SR Document Information Object Definitions

import Foundation
import DICOMCore

/// Parser for DICOM Structured Reporting documents
///
/// Converts a DICOM DataSet into an SRDocument with a hierarchical content tree.
///
/// Example:
/// ```swift
/// let parser = SRDocumentParser()
/// let document = try parser.parse(dataSet: dataSet)
/// ```
public struct SRDocumentParser: Sendable {
    
    /// Validation level for parsing
    public enum ValidationLevel: Sendable, Equatable {
        /// Strict validation - all required attributes must be present
        case strict
        
        /// Lenient validation - missing attributes are tolerated
        case lenient
    }
    
    /// Parser configuration
    public struct Configuration: Sendable {
        /// Validation level to use during parsing
        public let validationLevel: ValidationLevel
        
        /// Maximum depth for nested content items (to prevent stack overflow)
        public let maxDepth: Int
        
        /// Creates a parser configuration
        /// - Parameters:
        ///   - validationLevel: The validation level
        ///   - maxDepth: Maximum nesting depth (default: 100)
        public init(
            validationLevel: ValidationLevel = .lenient,
            maxDepth: Int = 100
        ) {
            self.validationLevel = validationLevel
            self.maxDepth = maxDepth
        }
        
        /// Default configuration with lenient validation
        public static let `default` = Configuration()
        
        /// Strict configuration for conformance testing
        public static let strict = Configuration(validationLevel: .strict)
    }
    
    /// Parser errors
    public enum ParseError: Error, Sendable, Equatable {
        /// Missing required attribute
        case missingRequiredAttribute(tag: String, description: String)
        
        /// Invalid or missing SOP Class UID
        case invalidSOPClassUID
        
        /// Invalid or missing SOP Instance UID
        case invalidSOPInstanceUID
        
        /// Unknown value type
        case unknownValueType(String)
        
        /// Invalid content sequence
        case invalidContentSequence(String)
        
        /// Maximum nesting depth exceeded
        case maxDepthExceeded(depth: Int)
        
        /// Invalid coded concept
        case invalidCodedConcept(String)
        
        /// Invalid graphic data for spatial coordinates
        case invalidGraphicData(String)
        
        /// Invalid referenced SOP sequence
        case invalidReferencedSOPSequence(String)
    }
    
    /// The parser configuration
    public let configuration: Configuration
    
    /// Creates a new SR document parser
    /// - Parameter configuration: Parser configuration
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Public Parsing API
    
    /// Parses a DICOM DataSet into an SRDocument
    /// - Parameter dataSet: The DICOM data set to parse
    /// - Returns: A parsed SR document
    /// - Throws: ParseError if parsing fails
    public func parse(dataSet: DataSet) throws -> SRDocument {
        // Extract required identifiers
        let sopClassUID = try extractRequiredString(from: dataSet, tag: .sopClassUID, description: "SOP Class UID")
        let sopInstanceUID = try extractRequiredString(from: dataSet, tag: .sopInstanceUID, description: "SOP Instance UID")
        
        // Patient Module (PS3.3 2026a Table C.7-1) and General Study Module (Table C.7-3):
        // the Type 2 attributes are read as nil when absent or zero length (value unknown)
        let patientID = type2String(dataSet, .patientID)
        let patientName = type2String(dataSet, .patientName)
        let patientBirthDate = type2String(dataSet, .patientBirthDate)
        let patientSex = type2String(dataSet, .patientSex)
        
        let studyInstanceUID = dataSet.string(for: .studyInstanceUID)
        let studyDate = type2String(dataSet, .studyDate)
        let studyTime = type2String(dataSet, .studyTime)
        let accessionNumber = type2String(dataSet, .accessionNumber)
        let referringPhysicianName = type2String(dataSet, .referringPhysicianName)
        let studyID = type2String(dataSet, .studyID)

        // General Equipment Module (Table C.7-8): Manufacturer (0008,0070), Type 2
        let manufacturer = type2String(dataSet, .manufacturer)
        
        // Extract optional series information
        let seriesInstanceUID = dataSet.string(for: .seriesInstanceUID)
        let seriesNumber = dataSet.string(for: .seriesNumber)
        let modality = dataSet.string(for: .modality)
        
        // Extract document header information
        let contentDate = dataSet.string(for: .contentDate)
        let contentTime = dataSet.string(for: .contentTime)
        let instanceNumber = dataSet.string(for: .instanceNumber)
        
        // Extract flags
        let completionFlag = dataSet.string(for: .completionFlag).flatMap { CompletionFlag(rawValue: $0) }
        let verificationFlag = dataSet.string(for: .verificationFlag).flatMap { VerificationFlag(rawValue: $0) }
        let preliminaryFlag = dataSet.string(for: .preliminaryFlag).flatMap { PreliminaryFlag(rawValue: $0) }

        // Verifying Observer Sequence (0040,A073), Type 1C (PS3.3 Table C.17-2)
        let verifyingObservers = parseVerifyingObservers(from: dataSet)
        
        // Parse document title from Concept Name Code Sequence
        let documentTitle = try? parseCodedConcept(from: dataSet, tag: .conceptNameCodeSequence)
        
        // Parse the content tree
        let rootContent = try parseRootContent(from: dataSet)
        
        return SRDocument(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            patientID: patientID,
            patientName: patientName,
            studyInstanceUID: studyInstanceUID,
            studyDate: studyDate,
            studyTime: studyTime,
            accessionNumber: accessionNumber,
            seriesInstanceUID: seriesInstanceUID,
            seriesNumber: seriesNumber,
            modality: modality,
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: instanceNumber,
            completionFlag: completionFlag,
            verificationFlag: verificationFlag,
            preliminaryFlag: preliminaryFlag,
            verifyingObservers: verifyingObservers,
            documentTitle: documentTitle,
            rootContent: rootContent,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName,
            studyID: studyID,
            manufacturer: manufacturer
        )
    }

    /// The value of a Type 2 attribute, or nil when it is absent or zero length
    private func type2String(_ dataSet: DataSet, _ tag: Tag) -> String? {
        guard let value = dataSet.string(for: tag), !value.isEmpty else { return nil }
        return value
    }

    /// Reads the Verifying Observer Sequence (0040,A073) Items (PS3.3 2026a Table C.17-2)
    ///
    /// Verifying Observer Name (0040,A075), Verifying Organization (0040,A027) and
    /// Verification DateTime (0040,A030) are Type 1; an Item that lacks one is read with an
    /// empty value rather than dropped, so the document is reported as it was received
    /// (and `SRDocumentSerializer` refuses to write it back unchanged). The Verifying
    /// Observer Identification Code Sequence (0040,A088) is Type 2 with zero or one Item.
    private func parseVerifyingObservers(from dataSet: DataSet) -> [VerifyingObserver] {
        guard let items = dataSet.sequence(for: .verifyingObserverSequence) else {
            return []
        }
        return items.map { item in
            VerifyingObserver(
                name: item.string(for: .verifyingObserverName) ?? "",
                identificationCode: (try? parseCodedConceptFromItem(item, tag: .verifyingObserverIdentificationCodeSequence)) ?? nil,
                organization: item.string(for: .verifyingOrganization) ?? "",
                verificationDateTime: item.string(for: .verificationDateTime) ?? ""
            )
        }
    }
    
    // MARK: - Content Parsing
    
    /// Parses the root content from the data set
    private func parseRootContent(from dataSet: DataSet) throws -> ContainerContentItem {
        // The root of an SR document is always a CONTAINER
        // Parse the Concept Name Code Sequence for the root
        let conceptName = try? parseCodedConcept(from: dataSet, tag: .conceptNameCodeSequence)
        
        // Parse Continuity of Content
        let continuityString = dataSet.string(for: .continuityOfContent)
        let continuity = continuityString.flatMap { ContinuityOfContent(rawValue: $0) } ?? .separate
        
        // Parse template identifier if present
        let templateIdentifier = parseTemplateIdentifier(from: dataSet)
        
        // Parse Content Sequence
        var contentItems: [AnyContentItem] = []
        if let contentSequence = dataSet.sequence(for: .contentSequence) {
            contentItems = try parseContentSequence(contentSequence, depth: 0)
        }
        
        return ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuity,
            contentItems: contentItems,
            templateIdentifier: templateIdentifier?.identifier,
            mappingResource: templateIdentifier?.mappingResource,
            relationshipType: nil,
            observationDateTime: dataSet.string(for: .observationDateTime),
            observationUID: nil
        )
    }
    
    /// Parses Content Sequence items recursively
    private func parseContentSequence(_ sequence: [SequenceItem], depth: Int) throws -> [AnyContentItem] {
        // Check maximum depth
        guard depth < configuration.maxDepth else {
            throw ParseError.maxDepthExceeded(depth: depth)
        }
        
        var contentItems: [AnyContentItem] = []
        
        for item in sequence {
            if let contentItem = try parseContentItem(from: item, depth: depth) {
                contentItems.append(contentItem)
            }
        }
        
        return contentItems
    }
    
    /// Parses a single content item from a sequence item
    private func parseContentItem(from item: SequenceItem, depth: Int) throws -> AnyContentItem? {
        // Get the Value Type (0040,A040)
        guard let valueTypeString = item.string(for: .valueType) else {
            if configuration.validationLevel == .strict {
                throw ParseError.missingRequiredAttribute(tag: "(0040,A040)", description: "Value Type")
            }
            return nil
        }
        
        guard let valueType = ContentItemValueType(rawValue: valueTypeString) else {
            if configuration.validationLevel == .strict {
                throw ParseError.unknownValueType(valueTypeString)
            }
            return nil
        }
        
        // Parse common attributes
        let conceptName = try? parseCodedConceptFromItem(item, tag: .conceptNameCodeSequence)
        let relationshipType = item.string(for: .relationshipType).flatMap { RelationshipType(rawValue: $0) }
        let observationDateTime = item.string(for: .observationDateTime)
        let observationUID = item.string(for: .observationUID)
        
        // Parse based on value type
        guard let parsed = try parseValue(of: valueType, from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID, depth: depth) else {
            return nil
        }

        // Content Sequence (0040,A730) of a non-CONTAINER item: PS3.3 Table C.17-6 gives
        // every content item one, so children under a CODE, NUM, IMAGE, SCOORD, ... item are
        // read as its children. CONTAINER reads its own in parseContainerContentItem.
        if valueType != .container, let contentSequence = item[.contentSequence]?.sequenceItems, !contentSequence.isEmpty {
            return parsed.withContentItems(try parseContentSequence(contentSequence, depth: depth + 1))
        }
        return parsed
    }

    /// Parses the value of a content item of the given value type
    private func parseValue(
        of valueType: ContentItemValueType,
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?,
        depth: Int
    ) throws -> AnyContentItem? {
        switch valueType {
        case .text:
            return try parseTextContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .code:
            return try parseCodeContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .num:
            return try parseNumericContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .date:
            return try parseDateContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .time:
            return try parseTimeContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .datetime:
            return try parseDateTimeContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .pname:
            return try parsePersonNameContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .uidref:
            return try parseUIDRefContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .composite:
            return try parseCompositeContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .image:
            return try parseImageContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .waveform:
            return try parseWaveformContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .scoord:
            return try parseSCoordContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .scoord3D:
            return try parseSCoord3DContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .tcoord:
            return try parseTCoordContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
            
        case .container:
            return try parseContainerContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID, depth: depth)

        case .table:
            return try parseTableContentItem(from: item, conceptName: conceptName, relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID)
        }
    }

    // MARK: - Table Content Item (PS3.3 C.18.10)

    private func parseTableContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        guard let table = item[.tabulatedValuesSequence]?.sequenceItems?.first else {
            throw ParseError.missingRequiredAttribute(tag: "(0040,A801)", description: "Tabulated Values Sequence")
        }
        let rows = Int(table[.numberOfTableRows]?.uint32Value ?? 0)
        let columns = Int(table[.numberOfTableColumns]?.uint32Value ?? 0)
        let rowDefs = try (table[.tableRowDefinitionSequence]?.sequenceItems ?? []).map { try parseAxisDefinition($0, numberTag: .tableRowNumber) }
        let colDefs = try (table[.tableColumnDefinitionSequence]?.sequenceItems ?? []).map { try parseAxisDefinition($0, numberTag: .tableColumnNumber) }
        let cells = try (table[.cellValuesSequence]?.sequenceItems ?? []).map(parseCell)
        return AnyContentItem(TableContentItem(
            conceptName: conceptName, rows: rows, columns: columns,
            rowDefinitions: rowDefs, columnDefinitions: colDefs, cells: cells,
            relationshipType: relationshipType, observationDateTime: observationDateTime, observationUID: observationUID))
    }

    private func parseAxisDefinition(_ item: SequenceItem, numberTag: Tag) throws -> TableContentItem.TableAxisDefinition {
        guard let concept = try parseCodedConceptFromItem(item, tag: .conceptNameCodeSequence) else {
            throw ParseError.missingRequiredAttribute(tag: "(0040,A043)", description: "Concept Name Code Sequence in table axis definition")
        }
        return TableContentItem.TableAxisDefinition(
            index: item[numberTag]?.uint32Value.map(Int.init),
            concept: concept,
            units: try parseCodedConceptFromItem(item, tag: .measurementUnitsCodeSequence))
    }

    private func parseCell(_ item: SequenceItem) throws -> TableContentItem.TableCell {
        let value: TableContentItem.TableCellValue
        if let ids = item[.referencedContentItemIdentifier]?.uint32Values {
            value = .contentItemReference(ids.map(Int.init))
        } else if let codeItems = item[.conceptCodeSequence]?.sequenceItems, !codeItems.isEmpty {
            value = .code(codeItems.compactMap { parseCodedConceptFromSequenceItem($0) })
        } else if let vr = item.string(for: .selectorAttributeVR)?.trimmingCharacters(in: .whitespaces) {
            switch vr {
            case "UC": value = .text(item[.selectorUCValue]?.stringValues ?? [])
            case "DS": value = .decimal(item[.selectorDSValue]?.decimalStringValues?.map(\.value) ?? [])
            case "DT": value = .dateTime(item[.selectorDTValue]?.stringValues ?? [])
            case "FD": value = .floatingPoint(item[.selectorFDValue]?.float64Values ?? [])
            case "FL": value = .floatingPoint(item[.selectorFLValue]?.float32Values?.map(Double.init) ?? [])
            case "IS": value = .integer(item[.selectorISValue]?.integerStringValues?.map { Int64($0.value) } ?? [])
            case "SL": value = .integer(item[.selectorSLValue]?.int32Values?.map(Int64.init) ?? [])
            case "SS": value = .integer(item[.selectorSSValue]?.int16Values?.map(Int64.init) ?? [])
            case "UL": value = .integer(item[.selectorULValue]?.uint32Values?.map(Int64.init) ?? [])
            case "US": value = .integer(item[.selectorUSValue]?.uint16Values?.map(Int64.init) ?? [])
            case "SV": value = .integer(item[.selectorSVValue]?.int64Values ?? [])
            case "UV": value = .integer(item[.selectorUVValue]?.uint64Values?.map { Int64(clamping: $0) } ?? [])
            default:
                throw ParseError.unknownValueType("TABLE cell Selector Attribute VR \(vr)")
            }
        } else {
            value = .absent
        }
        return TableContentItem.TableCell(
            row: item[.tableRowNumber]?.uint32Value.map(Int.init),
            column: item[.tableColumnNumber]?.uint32Value.map(Int.init),
            value: value,
            units: try parseCodedConceptFromItem(item, tag: .measurementUnitsCodeSequence),
            qualifier: try parseCodedConceptFromItem(item, tag: .numericValueQualifierCodeSequence))
    }
    
    // MARK: - Value Type Specific Parsers
    
    private func parseTextContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let textValue = item.string(for: .textValue) ?? ""
        
        return AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: textValue,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseCodeContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        guard let conceptCode = try? parseCodedConceptFromItem(item, tag: .conceptCodeSequence) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidCodedConcept("Missing Concept Code Sequence for CODE content item")
            }
            // Return with a placeholder code for lenient mode
            return AnyContentItem(CodeContentItem(
                conceptName: conceptName,
                conceptCode: CodedConcept(codeValue: "UNKNOWN", codingSchemeDesignator: "99LOCAL", codeMeaning: "Unknown"),
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        return AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: conceptCode,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseNumericContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        // Parse Measured Value Sequence (0040,A300) or direct Numeric Value (0040,A30A)
        var numericValues: [Double] = []
        var measurementUnits: CodedConcept?
        var floatingPointValues: [Double]?
        
        // Try Measured Value Sequence first
        if let measuredValueSeq = item[.measuredValueSequence]?.sequenceItems?.first {
            // Get Numeric Value from sequence
            if let numericValueStr = measuredValueSeq.string(for: .numericValue) {
                numericValues = numericValueStr.split(separator: "\\").compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }
            }
            
            // Get Floating Point Value if present
            if let floatData = measuredValueSeq[.floatingPointValue]?.float64Values {
                floatingPointValues = floatData
            }
            
            // Get Measurement Units Code Sequence
            measurementUnits = try? parseCodedConceptFromItem(measuredValueSeq, tag: .measurementUnitsCodeSequence)
        } else {
            // Try direct Numeric Value (0040,A30A)
            if let numericValueStr = item.string(for: .numericValue) {
                numericValues = numericValueStr.split(separator: "\\").compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }
            }
            
            // Try direct measurement units
            measurementUnits = try? parseCodedConceptFromItem(item, tag: .measurementUnitsCodeSequence)
        }
        
        // An empty Measured Value Sequence (0040,A300) is allowed: Type 2, "Zero or one
        // Item" (PS3.3 2026a Table C.18.1-1), and C.18.1 says it "may be empty to convey the
        // concept of a measurement whose value is unknown or missing, or a measurement or
        // calculation failure". The value stays absent (`numericValues` empty, `value` nil);
        // until 2026-10-01 (D194) the lenient parser fabricated 0.0.

        // Numeric Value Qualifier Code Sequence (0040,A301), Type 1C: "Required if Measured
        // Value Sequence (0040,A300) is empty", one Item from CID 42 (CIDs 43 and 44).
        // Read since 2026-10-01 (D195); a code outside CID 42 leaves the qualifier nil.
        let qualifier = (try? parseCodedConceptFromItem(item, tag: .numericValueQualifierCodeSequence))
            .flatMap { NumericValueQualifier(code: $0) }
        
        return AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: numericValues,
            units: measurementUnits,
            floatingPointValues: floatingPointValues,
            qualifier: qualifier,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseDateContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let dateValue = item.string(for: .date) ?? ""
        
        return AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: dateValue,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseTimeContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let timeValue = item.string(for: .time) ?? ""
        
        return AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: timeValue,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseDateTimeContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let dateTimeValue = item.string(for: .dateTime) ?? ""
        
        return AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: dateTimeValue,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parsePersonNameContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let personName = item.string(for: .personName) ?? ""
        
        return AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: personName,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseUIDRefContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        let uidValue = item.string(for: .uid) ?? ""
        
        return AnyContentItem(UIDRefContentItem(
            conceptName: conceptName,
            uidValue: uidValue,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseCompositeContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        guard let sopRef = try parseReferencedSOPSequence(from: item) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidReferencedSOPSequence("Missing Referenced SOP Sequence for COMPOSITE content item")
            }
            // Return placeholder in lenient mode
            return AnyContentItem(CompositeContentItem(
                conceptName: conceptName,
                referencedSOPSequence: ReferencedSOP(sopClassUID: "", sopInstanceUID: ""),
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        return AnyContentItem(CompositeContentItem(
            conceptName: conceptName,
            referencedSOPSequence: sopRef,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseImageContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        guard let sopRef = try parseReferencedSOPSequence(from: item) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidReferencedSOPSequence("Missing Referenced SOP Sequence for IMAGE content item")
            }
            // Return placeholder in lenient mode
            return AnyContentItem(ImageContentItem(
                conceptName: conceptName,
                imageReference: ImageReference(sopReference: ReferencedSOP(sopClassUID: "", sopInstanceUID: "")),
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        // Parse frame numbers if present
        var frameNumbers: [Int]?
        if let refSOPSeq = item[.referencedSOPSequence]?.sequenceItems?.first {
            if let frameNumStr = refSOPSeq.string(for: .referencedFrameNumber) {
                frameNumbers = frameNumStr.split(separator: "\\").compactMap { Int(String($0).trimmingCharacters(in: .whitespaces)) }
            }
        }
        
        // Parse segment numbers if present
        var segmentNumbers: [Int]?
        if let refSOPSeq = item[.referencedSOPSequence]?.sequenceItems?.first {
            if let segmentNumData = refSOPSeq[.referencedSegmentNumber]?.uint16Values {
                segmentNumbers = segmentNumData.map { Int($0) }
            }
        }
        
        // Parse purpose of reference if present
        var purposeOfReference: CodedConcept?
        if let refSOPSeq = item[.referencedSOPSequence]?.sequenceItems?.first {
            purposeOfReference = try? parseCodedConceptFromItem(refSOPSeq, tag: .purposeOfReferenceCodeSequence)
        }
        
        let imageRef = ImageReference(
            sopReference: sopRef,
            frameNumbers: frameNumbers,
            segmentNumbers: segmentNumbers,
            purposeOfReference: purposeOfReference
        )
        
        return AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            imageReference: imageRef,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseWaveformContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        guard let sopRef = try parseReferencedSOPSequence(from: item) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidReferencedSOPSequence("Missing Referenced SOP Sequence for WAVEFORM content item")
            }
            // Return placeholder in lenient mode
            return AnyContentItem(WaveformContentItem(
                conceptName: conceptName,
                waveformReference: WaveformReference(sopReference: ReferencedSOP(sopClassUID: "", sopInstanceUID: "")),
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        // Referenced Waveform Channels (0040,A0B0), US, VM 2-2n, Type 1C (PS3.3 2026a
        // Table C.18.5-1): (M,C) pairs of Multiplex Group Number and Channel Number
        // (C.18.5.1.1). Both halves are kept in `referencedChannels`; `channelNumbers` keeps
        // the C values as before.
        var referencedChannels: [WaveformChannelReference]?
        if let refSOPSeq = item[.referencedSOPSequence]?.sequenceItems?.first,
           let channelData = refSOPSeq[SRDocumentSerializer.referencedWaveformChannelsTag]?.uint16Values,
           channelData.count >= 2 {
            referencedChannels = stride(from: 0, to: channelData.count - 1, by: 2).map {
                WaveformChannelReference(multiplexGroup: Int(channelData[$0]), channel: Int(channelData[$0 + 1]))
            }
        }
        
        let waveformRef = WaveformReference(sopReference: sopRef, referencedChannels: referencedChannels)
        
        return AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseSCoordContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        // Parse Graphic Type (0070,0023)
        let graphicTypeTag = Tag(group: 0x0070, element: 0x0023)
        guard let graphicTypeStr = item.string(for: graphicTypeTag),
              let graphicType = GraphicType(rawValue: graphicTypeStr) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidGraphicData("Missing or invalid Graphic Type for SCOORD content item")
            }
            return AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: conceptName,
                graphicType: .point,
                graphicData: [],
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        // Parse Graphic Data (0070,0022)
        let graphicDataTag = Tag(group: 0x0070, element: 0x0022)
        let graphicData = item[graphicDataTag]?.float32Values ?? []
        
        return AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseSCoord3DContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        // Parse Graphic Type (0070,0023)
        let graphicTypeTag = Tag(group: 0x0070, element: 0x0023)
        guard let graphicTypeStr = item.string(for: graphicTypeTag),
              let graphicType = GraphicType3D(rawValue: graphicTypeStr) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidGraphicData("Missing or invalid Graphic Type for SCOORD3D content item")
            }
            return AnyContentItem(SpatialCoordinates3DContentItem(
                conceptName: conceptName,
                graphicType: .point,
                graphicData: [],
                frameOfReferenceUID: nil,
                relationshipType: relationshipType,
                observationDateTime: observationDateTime,
                observationUID: observationUID
            ))
        }
        
        // Parse Graphic Data (0070,0022)
        let graphicDataTag = Tag(group: 0x0070, element: 0x0022)
        let graphicData = item[graphicDataTag]?.float32Values ?? []
        
        // Referenced Frame of Reference UID (3006,0024), Type 1 of the 3D Spatial
        // Coordinates Macro (PS3.3 Table C.18.9-1); (0020,0052) is what this serializer
        // wrote before the 2026a check and is still read.
        let frameOfReferenceUID = item.string(for: .referencedFrameOfReferenceUID)
            ?? item.string(for: Tag(group: 0x0020, element: 0x0052))
        
        return AnyContentItem(SpatialCoordinates3DContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    private func parseTCoordContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?
    ) throws -> AnyContentItem {
        // Parse Temporal Range Type (0040,A130)
        let temporalRangeTypeTag = Tag(group: 0x0040, element: 0xA130)
        guard let temporalRangeTypeStr = item.string(for: temporalRangeTypeTag),
              let temporalRangeType = TemporalRangeType(rawValue: temporalRangeTypeStr) else {
            if configuration.validationLevel == .strict {
                throw ParseError.invalidGraphicData("Missing or invalid Temporal Range Type for TCOORD content item")
            }
            return AnyContentItem(TemporalCoordinatesContentItem(
                conceptName: conceptName,
                temporalRangeType: .point,
                samplePositions: [],
                relationshipType: relationshipType
            ))
        }
        
        // Try to parse Referenced Sample Positions (0040,A132)
        let samplePositionsTag = Tag(group: 0x0040, element: 0xA132)
        if let samplePositions = item[samplePositionsTag]?.uint32Values {
            return AnyContentItem(TemporalCoordinatesContentItem(
                conceptName: conceptName,
                temporalRangeType: temporalRangeType,
                samplePositions: samplePositions,
                relationshipType: relationshipType
            ))
        }
        
        // Try to parse Referenced Time Offsets (0040,A138)
        let timeOffsetsTag = Tag(group: 0x0040, element: 0xA138)
        if let timeOffsetStr = item.string(for: timeOffsetsTag) {
            let timeOffsets = timeOffsetStr.split(separator: "\\").compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }
            return AnyContentItem(TemporalCoordinatesContentItem(
                conceptName: conceptName,
                temporalRangeType: temporalRangeType,
                timeOffsets: timeOffsets,
                relationshipType: relationshipType
            ))
        }
        
        // Try to parse Referenced DateTime (0040,A13A)
        let dateTimeTag = Tag(group: 0x0040, element: 0xA13A)
        if let dateTimeStr = item.string(for: dateTimeTag) {
            let dateTimes = dateTimeStr.split(separator: "\\").map { String($0) }
            return AnyContentItem(TemporalCoordinatesContentItem(
                conceptName: conceptName,
                temporalRangeType: temporalRangeType,
                dateTimes: dateTimes,
                relationshipType: relationshipType
            ))
        }
        
        // Return empty if no temporal data found
        return AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            samplePositions: [],
            relationshipType: relationshipType
        ))
    }
    
    private func parseContainerContentItem(
        from item: SequenceItem,
        conceptName: CodedConcept?,
        relationshipType: RelationshipType?,
        observationDateTime: String?,
        observationUID: String?,
        depth: Int
    ) throws -> AnyContentItem {
        // Parse Continuity of Content
        let continuityString = item.string(for: .continuityOfContent)
        let continuity = continuityString.flatMap { ContinuityOfContent(rawValue: $0) } ?? .separate
        
        // Parse template identifier if present
        let templateIdentifier = parseTemplateIdentifierFromItem(item)
        
        // Parse nested Content Sequence
        var contentItems: [AnyContentItem] = []
        if let contentSequence = item[.contentSequence]?.sequenceItems {
            contentItems = try parseContentSequence(contentSequence, depth: depth + 1)
        }
        
        return AnyContentItem(ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuity,
            contentItems: contentItems,
            templateIdentifier: templateIdentifier?.identifier,
            mappingResource: templateIdentifier?.mappingResource,
            relationshipType: relationshipType,
            observationDateTime: observationDateTime,
            observationUID: observationUID
        ))
    }
    
    // MARK: - Helper Methods
    
    private func extractRequiredString(from dataSet: DataSet, tag: Tag, description: String) throws -> String {
        guard let value = dataSet.string(for: tag), !value.isEmpty else {
            if configuration.validationLevel == .strict {
                throw ParseError.missingRequiredAttribute(tag: tag.description, description: description)
            }
            return ""
        }
        return value
    }
    
    /// Parses a coded concept from a sequence at the given tag
    private func parseCodedConcept(from dataSet: DataSet, tag: Tag) throws -> CodedConcept? {
        guard let sequence = dataSet.sequence(for: tag),
              let firstItem = sequence.first else {
            return nil
        }
        return parseCodedConceptFromSequenceItem(firstItem)
    }
    
    /// Parses a coded concept from a sequence item at the given tag
    private func parseCodedConceptFromItem(_ item: SequenceItem, tag: Tag) throws -> CodedConcept? {
        guard let sequence = item[tag]?.sequenceItems,
              let firstItem = sequence.first else {
            return nil
        }
        return parseCodedConceptFromSequenceItem(firstItem)
    }
    
    /// Parses a coded concept from a sequence item containing code attributes
    ///
    /// PS3.3 Table 8.8-1a: exactly one of Code Value (0008,0100), Long Code Value
    /// (0008,0119) or URN Code Value (0008,0120) is present; Code Meaning (0008,0104) is
    /// Type 1; Coding Scheme Designator (0008,0102) is Type 1C, required with Code Value or
    /// Long Code Value and optional with URN Code Value. The parser mirrors
    /// `SRDocumentSerializer`: `codeValue` holds the Code Value, or "" when the identifier
    /// is a Long or URN Code Value, and Items that (against the macro) carry more than one
    /// identifier keep all of them.
    private func parseCodedConceptFromSequenceItem(_ item: SequenceItem) -> CodedConcept? {
        let codeValue = item.string(for: .codeValue)
        let longCodeValue = item.string(for: .longCodeValue)
        let urnCodeValue = item.string(for: .urnCodeValue)

        // At least one identifier must be present
        guard codeValue != nil || longCodeValue != nil || urnCodeValue != nil else {
            return nil
        }

        // Code Meaning is Type 1
        guard let codeMeaning = item.string(for: .codeMeaning) else {
            return nil
        }

        // Coding Scheme Designator: required unless the identifier is a URN Code Value alone
        let designator = item.string(for: .codingSchemeDesignator)
        let identifiedByURNOnly = codeValue == nil && longCodeValue == nil && urnCodeValue != nil
        guard let codingSchemeDesignator = designator ?? (identifiedByURNOnly ? "" : nil) else {
            return nil
        }

        return CodedConcept(
            codeValue: codeValue ?? "",
            codingSchemeDesignator: codingSchemeDesignator,
            codeMeaning: codeMeaning,
            codingSchemeVersion: item.string(for: .codingSchemeVersion),
            longCodeValue: longCodeValue,
            urnCodeValue: urnCodeValue
        )
    }
    
    /// Parses Referenced SOP Sequence from a content item
    private func parseReferencedSOPSequence(from item: SequenceItem) throws -> ReferencedSOP? {
        guard let refSOPSeq = item[.referencedSOPSequence]?.sequenceItems?.first else {
            return nil
        }
        
        guard let sopClassUID = refSOPSeq.string(for: .referencedSOPClassUID),
              let sopInstanceUID = refSOPSeq.string(for: .referencedSOPInstanceUID) else {
            return nil
        }
        
        return ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
    }
    
    /// Template identifier info
    private struct TemplateInfo {
        let identifier: String
        let mappingResource: String?
    }
    
    /// Parses template identifier from a data set
    private func parseTemplateIdentifier(from dataSet: DataSet) -> TemplateInfo? {
        guard let templateSeq = dataSet.sequence(for: .contentTemplateSequence),
              let firstItem = templateSeq.first else {
            return nil
        }
        
        guard let templateID = firstItem.string(for: .templateIdentifier) else {
            return nil
        }
        
        let mappingResource = firstItem.string(for: .mappingResource)
        
        return TemplateInfo(identifier: templateID, mappingResource: mappingResource)
    }
    
    /// Parses template identifier from a sequence item
    private func parseTemplateIdentifierFromItem(_ item: SequenceItem) -> TemplateInfo? {
        guard let templateSeq = item[.contentTemplateSequence]?.sequenceItems,
              let firstItem = templateSeq.first else {
            return nil
        }
        
        guard let templateID = firstItem.string(for: .templateIdentifier) else {
            return nil
        }
        
        let mappingResource = firstItem.string(for: .mappingResource)
        
        return TemplateInfo(identifier: templateID, mappingResource: mappingResource)
    }
}

// MARK: - Additional Tag Extensions for SR Parsing
// Note: contentDate and contentTime are already defined in Tag+ImageInformation.swift

extension Tag {
    /// Measured Value Sequence (0040,A300)
    /// VR: SQ, VM: 1
    static let measuredValueSequence = Tag(group: 0x0040, element: 0xA300)
    
    /// Floating Point Value (0040,A161)
    /// VR: FD, VM: 1-n
    static let floatingPointValue = Tag(group: 0x0040, element: 0xA161)
    
    /// Observation UID (0040,A171)
    /// VR: UI, VM: 1
    static let observationUID = Tag(group: 0x0040, element: 0xA171)
}
