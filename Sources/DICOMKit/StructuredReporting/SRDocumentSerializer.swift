// NEMA-verified: 2026a, checked 2026-09-30 — SR Document Series Module per PS3.3 2026a Table C.17-1 (Modality SR, Table C.17.6-1 KO; Referenced PPS Sequence Type 2), SR Document General Module per Table C.17-2 (Type 1 Instance Number, Completion/Verification Flag, Content Date/Time; Verifying Observer Sequence Type 1C when VERIFIED, absent otherwise per PS3.5 7.4.2, Item attributes A075/A027/A030 Type 1 and A088 Type 2; Performed Procedure Code Sequence Type 2), Code Sequence Macro per Table 8.8-1a (exactly one of Code Value / Long Code Value / URN Code Value), TABLE cells per Table C.18.10-1 (IS or SV integer cells), SCOORD3D (3006,0024) per Table C.18.9-1; Content Sequence (0040,A730) nested in every value type per Table C.17-6 (D31)
// NEMA-verified: 2026a, checked 2026-10-01 — Patient (Table C.7-1: 4 Type 2 rows), General Study (Table C.7-3: Study Instance UID Type 1 and 5 Type 2 rows) and General Equipment (Table C.7-8: Manufacturer Type 2) Modules written per PS3.3 2026a Table A.35.3-1, zero length when unknown (D198); NUM with no value: empty Measured Value Sequence plus Numeric Value Qualifier Code Sequence per Table C.18.1-1 (D194, D195); Referenced Waveform Channels (0040,A0B0) US (M,C) pairs per Table C.18.5-1 / C.18.5.1.1 (D196)
/// DICOM Structured Reporting Document Serializer
///
/// Converts SRDocument objects to DICOM DataSet format for storage.
///
/// Reference: PS3.3 Section C.17 - SR Document Information Object Definitions

import Foundation
import DICOMCore

/// Serializer for converting SRDocument to DICOM DataSet
///
/// Example:
/// ```swift
/// let serializer = SRDocumentSerializer()
/// let dataSet = try serializer.serialize(document: srDocument)
/// ```
public struct SRDocumentSerializer: Sendable {
    
    /// Serialization errors
    public enum SerializationError: Error, Sendable, Equatable {
        /// Missing required attribute
        case missingRequiredAttribute(String)
        
        /// Invalid content item
        case invalidContentItem(String)
        
        /// Encoding error
        case encodingError(String)

        /// Two attributes hold values the standard forbids together, e.g. Verification Flag
        /// VERIFIED with Completion Flag PARTIAL (PS3.3 Table C.17-2: "A Value of VERIFIED
        /// shall be used only when the Value of Completion Flag (0040,A491) is COMPLETE").
        case inconsistentAttributes(String)
    }
    
    /// Creates a new SR document serializer
    public init() {}

    /// Referenced Waveform Channels (0040,A0B0), US, VM 2-2n (PS3.6 2026a Table 6-1)
    static let referencedWaveformChannelsTag = Tag(group: 0x0040, element: 0xA0B0)
    
    // MARK: - Public API
    
    /// Serializes an SRDocument to a DataSet
    /// - Parameter document: The SR document to serialize
    /// - Returns: A DICOM DataSet representation
    /// - Throws: `SerializationError` if serialization fails
    public func serialize(document: SRDocument) throws -> DataSet {
        var dataSet = DataSet()
        
        // Add SOP Common Module
        addSOPCommonModule(to: &dataSet, document: document)
        
        // Add Patient Module
        addPatientModule(to: &dataSet, document: document)
        
        // Add General Study Module
        addGeneralStudyModule(to: &dataSet, document: document)

        // Add General Equipment Module
        addGeneralEquipmentModule(to: &dataSet, document: document)
        
        // Add SR Document Series Module (PS3.3 Table C.17-1; every A.35.x SR IOD except
        // Key Object Selection / Rendition Selection, which carry Table C.17.6-1)
        addSRDocumentSeriesModule(to: &dataSet, document: document)

        // Add SR Document General Module
        try addSRDocumentGeneralModule(to: &dataSet, document: document)
        
        // Add SR Document Content Module
        try addSRDocumentContentModule(to: &dataSet, document: document)
        
        return dataSet
    }
    
    // MARK: - SOP Common Module
    
    private func addSOPCommonModule(to dataSet: inout DataSet, document: SRDocument) {
        // SOP Class UID (0008,0016)
        dataSet[.sopClassUID] = DataElement.string(
            tag: .sopClassUID,
            vr: .UI,
            value: document.sopClassUID
        )
        
        // SOP Instance UID (0008,0018)
        dataSet[.sopInstanceUID] = DataElement.string(
            tag: .sopInstanceUID,
            vr: .UI,
            value: document.sopInstanceUID
        )
    }
    
    // MARK: - Patient Module (PS3.3 Table C.7-1)

    /// Writes a Type 2 attribute: its value, or zero length when the document has none
    /// (PS3.5 7.4.1: a Type 2 attribute "shall be present ... with a zero length if the
    /// Value is unknown")
    private func setType2(_ value: String?, tag: Tag, vr: VR, in dataSet: inout DataSet) {
        dataSet[tag] = DataElement.string(tag: tag, vr: vr, value: value ?? "")
    }

    private func addPatientModule(to dataSet: inout DataSet, document: SRDocument) {
        // Patient's Name (0010,0010), Patient ID (0010,0020), Patient's Birth Date
        // (0010,0030), Patient's Sex (0010,0040): all Type 2 in PS3.3 2026a Table C.7-1
        setType2(document.patientName, tag: .patientName, vr: .PN, in: &dataSet)
        setType2(document.patientID, tag: .patientID, vr: .LO, in: &dataSet)
        setType2(document.patientBirthDate, tag: .patientBirthDate, vr: .DA, in: &dataSet)
        setType2(document.patientSex, tag: .patientSex, vr: .CS, in: &dataSet)
    }

    // MARK: - General Study Module (PS3.3 Table C.7-3)

    private func addGeneralStudyModule(to dataSet: inout DataSet, document: SRDocument) {
        // Study Instance UID (0020,000D), Type 1. Documents built without one (the
        // builders generate one) are written without it rather than with a fabricated UID.
        if let studyInstanceUID = document.studyInstanceUID {
            dataSet[.studyInstanceUID] = DataElement.string(
                tag: .studyInstanceUID,
                vr: .UI,
                value: studyInstanceUID
            )
        }

        // Study Date (0008,0020), Study Time (0008,0030), Referring Physician's Name
        // (0008,0090), Study ID (0020,0010), Accession Number (0008,0050): Type 2
        setType2(document.studyDate, tag: .studyDate, vr: .DA, in: &dataSet)
        setType2(document.studyTime, tag: .studyTime, vr: .TM, in: &dataSet)
        setType2(document.referringPhysicianName, tag: .referringPhysicianName, vr: .PN, in: &dataSet)
        setType2(document.studyID, tag: .studyID, vr: .SH, in: &dataSet)
        setType2(document.accessionNumber, tag: .accessionNumber, vr: .SH, in: &dataSet)
    }

    // MARK: - General Equipment Module (PS3.3 Table C.7-8)

    private func addGeneralEquipmentModule(to dataSet: inout DataSet, document: SRDocument) {
        // Manufacturer (0008,0070), Type 2; the module is M in every SR IOD (e.g. Table A.35.3-1)
        setType2(document.manufacturer, tag: .manufacturer, vr: .LO, in: &dataSet)
    }
    
    // MARK: - SR Document Series Module (PS3.3 Table C.17-1)

    /// Series Number (0020,0011) and Instance Number (0020,0013) are Type 1 in Tables
    /// C.17-1 and C.17-2; this is what is written when the document carries none.
    public static let defaultNumber = "1"

    /// The Modality (0008,0060) written when the document carries none: the single
    /// Enumerated Value of Table C.17-1 ("SR") or, for the Key Object Selection and
    /// Rendition Selection Document IODs (Tables A.35.4-1 and A.35.21-1, Key Object
    /// Document Series Module), the single Enumerated Value of Table C.17.6-1 ("KO").
    public static func defaultModality(forSOPClassUID sopClassUID: String) -> String {
        switch SRDocumentType.from(sopClassUID: sopClassUID) {
        case .keyObjectSelectionDocument?: return "KO"
        default: return "SR"
        }
    }

    private func addSRDocumentSeriesModule(to dataSet: inout DataSet, document: SRDocument) {
        // Modality (0008,0060), Type 1
        dataSet[.modality] = DataElement.string(
            tag: .modality,
            vr: .CS,
            value: document.modality ?? Self.defaultModality(forSOPClassUID: document.sopClassUID)
        )

        // Series Instance UID (0020,000E), Type 1. Documents built without one (the
        // builders generate one) are written without it rather than with a fabricated UID.
        if let seriesInstanceUID = document.seriesInstanceUID {
            dataSet[.seriesInstanceUID] = DataElement.string(
                tag: .seriesInstanceUID,
                vr: .UI,
                value: seriesInstanceUID
            )
        }

        // Series Number (0020,0011), Type 1
        dataSet[.seriesNumber] = DataElement.string(
            tag: .seriesNumber,
            vr: .IS,
            value: document.seriesNumber ?? Self.defaultNumber
        )

        // Referenced Performed Procedure Step Sequence (0008,1111), Type 2: "Zero or one
        // Item shall be included". SRDocument does not model the PPS, so it is written empty.
        dataSet[.referencedPerformedProcedureStepSequence] = createSequenceElement(
            tag: .referencedPerformedProcedureStepSequence,
            items: []
        )
    }

    // MARK: - SR Document General Module (PS3.3 Table C.17-2)

    private func addSRDocumentGeneralModule(to dataSet: inout DataSet, document: SRDocument) throws {
        // Instance Number (0020,0013), Type 1
        dataSet[.instanceNumber] = DataElement.string(
            tag: .instanceNumber,
            vr: .IS,
            value: document.instanceNumber ?? Self.defaultNumber
        )

        // Completion Flag (0040,A491), Type 1, Enumerated Values PARTIAL / COMPLETE.
        // A document that does not say is written as PARTIAL ("Partial content"): the
        // value that claims nothing about completeness (C.17.2.7 leaves the criteria for
        // COMPLETE to the creating application).
        let completionFlag = document.completionFlag ?? .partial

        // Verification Flag (0040,A493), Type 1, Enumerated Values UNVERIFIED / VERIFIED.
        // Default UNVERIFIED ("Not attested to"); VERIFIED additionally requires the
        // Verifying Observer Sequence (Type 1C) and Completion Flag COMPLETE.
        let verificationFlag = document.verificationFlag ?? .unverified
        if verificationFlag == .verified && completionFlag != .complete {
            throw SerializationError.inconsistentAttributes(
                "Verification Flag VERIFIED requires Completion Flag COMPLETE (PS3.3 Table C.17-2); got \(completionFlag.rawValue)"
            )
        }
        let verifyingObserverItems = try verifyingObserverSequenceItems(
            document.verifyingObservers, verificationFlag: verificationFlag)

        dataSet[.completionFlag] = DataElement.string(
            tag: .completionFlag,
            vr: .CS,
            value: completionFlag.rawValue
        )
        dataSet[.verificationFlag] = DataElement.string(
            tag: .verificationFlag,
            vr: .CS,
            value: verificationFlag.rawValue
        )
        if let verifyingObserverItems {
            dataSet[.verifyingObserverSequence] = createSequenceElement(
                tag: .verifyingObserverSequence,
                items: verifyingObserverItems
            )
        }

        // Content Date (0008,0023) and Content Time (0008,0033), Type 1: "the date/time
        // the document content creation started". When the document carries neither, the
        // moment of serialization is used.
        let (nowDate, nowTime) = Self.currentDateAndTime()
        dataSet[.contentDate] = DataElement.string(
            tag: .contentDate,
            vr: .DA,
            value: document.contentDate ?? nowDate
        )
        dataSet[.contentTime] = DataElement.string(
            tag: .contentTime,
            vr: .TM,
            value: document.contentTime ?? nowTime
        )

        // Performed Procedure Code Sequence (0040,A372), Type 2: "Zero or more Items shall
        // be included". SRDocument does not model it, so it is written empty.
        dataSet[.performedProcedureCodeSequence] = createSequenceElement(
            tag: .performedProcedureCodeSequence,
            items: []
        )

        // Preliminary Flag (0040,A496)
        if let preliminaryFlag = document.preliminaryFlag {
            dataSet[.preliminaryFlag] = DataElement.string(
                tag: .preliminaryFlag,
                vr: .CS,
                value: preliminaryFlag.rawValue
            )
        }
    }

    /// Verifying Observer Sequence (0040,A073) Items, or nil when the sequence is not written
    ///
    /// PS3.3 2026a Table C.17-2: the sequence is Type 1C, "Required if Verification Flag
    /// (0040,A493) is VERIFIED", and "One or more Items shall be included". Each Item holds
    /// Verifying Observer Name (0040,A075) Type 1, Verifying Observer Identification Code
    /// Sequence (0040,A088) Type 2 ("Zero or one Item"), Verifying Organization (0040,A027)
    /// Type 1 and Verification DateTime (0040,A030) Type 1. PS3.5 2026a 7.4.2: when the
    /// condition is not met a Type 1C element "shall not be included" unless the table says
    /// it may be present otherwise, which C.17-2 does not.
    private func verifyingObserverSequenceItems(
        _ observers: [VerifyingObserver],
        verificationFlag: VerificationFlag
    ) throws -> [SequenceItem]? {
        guard verificationFlag == .verified else {
            if !observers.isEmpty {
                throw SerializationError.inconsistentAttributes(
                    "Verifying Observer Sequence (0040,A073) is Type 1C, required only if Verification Flag is VERIFIED; got \(verificationFlag.rawValue) with \(observers.count) observer(s) (PS3.3 Table C.17-2, PS3.5 7.4.2)"
                )
            }
            return nil
        }
        guard !observers.isEmpty else {
            throw SerializationError.missingRequiredAttribute(
                "Verifying Observer Sequence (0040,A073): one or more Items required when Verification Flag is VERIFIED (PS3.3 Table C.17-2)"
            )
        }
        return try observers.map { observer in
            // Type 1 attributes must have a value (PS3.5 7.4.1)
            for (value, name) in [
                (observer.name, "Verifying Observer Name (0040,A075)"),
                (observer.organization, "Verifying Organization (0040,A027)"),
                (observer.verificationDateTime, "Verification DateTime (0040,A030)"),
            ] where value.trimmingCharacters(in: .whitespaces).isEmpty {
                throw SerializationError.missingRequiredAttribute("\(name) is Type 1 in the Verifying Observer Sequence (PS3.3 Table C.17-2)")
            }
            return SequenceItem(elements: [
                DataElement.string(tag: .verifyingObserverName, vr: .PN, value: observer.name),
                createSequenceElement(
                    tag: .verifyingObserverIdentificationCodeSequence,
                    items: observer.identificationCode.map { [createCodeSequenceItem(code: $0)] } ?? []
                ),
                DataElement.string(tag: .verifyingOrganization, vr: .LO, value: observer.organization),
                DataElement.string(tag: .verificationDateTime, vr: .DT, value: observer.verificationDateTime),
            ])
        }
    }

    /// The current moment as a DA ("YYYYMMDD") and a TM ("HHMMSS") value.
    private static func currentDateAndTime() -> (String, String) {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: now)
        formatter.dateFormat = "HHmmss"
        let time = formatter.string(from: now)
        return (date, time)
    }
    
    // MARK: - SR Document Content Module
    
    private func addSRDocumentContentModule(to dataSet: inout DataSet, document: SRDocument) throws {
        // Value Type - root is always CONTAINER
        dataSet[.valueType] = DataElement.string(
            tag: .valueType,
            vr: .CS,
            value: ContentItemValueType.container.rawValue
        )
        
        // Concept Name Code Sequence (Document Title)
        if let documentTitle = document.documentTitle {
            dataSet[.conceptNameCodeSequence] = try createCodeSequenceElement(
                tag: .conceptNameCodeSequence,
                code: documentTitle
            )
        }
        
        // Continuity of Content
        dataSet[.continuityOfContent] = DataElement.string(
            tag: .continuityOfContent,
            vr: .CS,
            value: document.rootContent.continuityOfContent.rawValue
        )
        
        // Content Template Sequence (if template is specified)
        if let templateID = document.rootContent.templateIdentifier {
            dataSet[.contentTemplateSequence] = createTemplateSequenceElement(
                templateIdentifier: templateID,
                mappingResource: document.rootContent.mappingResource ?? "DCMR"
            )
        }
        
        // Content Sequence (the content tree)
        if !document.rootContent.contentItems.isEmpty {
            dataSet[.contentSequence] = try createContentSequenceElement(
                items: document.rootContent.contentItems
            )
        }
    }
    
    // MARK: - Code Sequence Creation
    
    /// Creates a Code Sequence element from a CodedConcept
    private func createCodeSequenceElement(tag: Tag, code: CodedConcept) throws -> DataElement {
        let sequenceItem = createCodeSequenceItem(code: code)
        return createSequenceElement(tag: tag, items: [sequenceItem])
    }
    
    /// Which of the three identifier attributes of PS3.3 Table 8.8-1a a coded concept is
    /// written with. Exactly one is present:
    /// - Code Value (0008,0100) "shall be present if the length of the code value is 16
    ///   characters or less, and the code value is not a URN or URL";
    /// - Long Code Value (0008,0119) "shall be present if Code Value is not present and the
    ///   Code Value is not a URN or URL";
    /// - URN Code Value (0008,0120) "shall be present if Code Value is not present and the
    ///   Code Value is a URN or URL".
    enum CodeIdentifier: Equatable {
        case codeValue(String)
        case longCodeValue(String)
        case urnCodeValue(String)

        init(_ code: CodedConcept) {
            let short = code.codeValue
            if !short.isEmpty, short.count <= 16, !Self.looksLikeURN(short) {
                self = .codeValue(short)
            } else if let urn = code.urnCodeValue, !urn.isEmpty {
                self = .urnCodeValue(urn)
            } else if let long = code.longCodeValue, !long.isEmpty {
                self = .longCodeValue(long)
            } else if Self.looksLikeURN(short) {
                self = .urnCodeValue(short)
            } else if !short.isEmpty {
                self = .longCodeValue(short)
            } else {
                // Nothing to write; an empty Code Value keeps the Item well-formed.
                self = .codeValue("")
            }
        }

        private static func looksLikeURN(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.hasPrefix("urn:") || lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }
    }

    /// Creates a sequence item for a coded concept (PS3.3 Table 8.8-1a Basic Code Sequence Macro)
    private func createCodeSequenceItem(code: CodedConcept) -> SequenceItem {
        var elements: [DataElement] = []

        let identifier = CodeIdentifier(code)
        switch identifier {
        case .codeValue(let value):
            // Code Value (0008,0100), SH
            elements.append(DataElement.string(tag: .codeValue, vr: .SH, value: value))
        case .longCodeValue(let value):
            // Long Code Value (0008,0119), UC
            elements.append(DataElement.string(tag: .longCodeValue, vr: .UC, value: value))
        case .urnCodeValue(let value):
            // URN Code Value (0008,0120), UR
            elements.append(DataElement.string(tag: .urnCodeValue, vr: .UR, value: value))
        }

        // Coding Scheme Designator (0008,0102), Type 1C: "Shall be present if Code Value or
        // Long Code Value is present. May be present otherwise."
        let designatorWritten: Bool
        if case .urnCodeValue = identifier, code.codingSchemeDesignator.isEmpty {
            designatorWritten = false
        } else {
            elements.append(DataElement.string(
                tag: .codingSchemeDesignator,
                vr: .SH,
                value: code.codingSchemeDesignator
            ))
            designatorWritten = true
        }

        // Coding Scheme Version (0008,0103), Type 1C: "Shall not be present if Coding Scheme
        // Designator is absent."
        if designatorWritten, let version = code.codingSchemeVersion {
            elements.append(DataElement.string(
                tag: .codingSchemeVersion,
                vr: .SH,
                value: version
            ))
        }

        // Code Meaning (0008,0104), Type 1
        elements.append(DataElement.string(
            tag: .codeMeaning,
            vr: .LO,
            value: code.codeMeaning
        ))

        return SequenceItem(elements: elements)
    }
    
    // MARK: - Template Sequence Creation
    
    /// Creates a Content Template Sequence element
    private func createTemplateSequenceElement(templateIdentifier: String, mappingResource: String) -> DataElement {
        var elements: [DataElement] = []
        
        // Template Identifier (0040,DB00)
        elements.append(DataElement.string(
            tag: .templateIdentifier,
            vr: .CS,
            value: templateIdentifier
        ))
        
        // Mapping Resource (0008,0105)
        elements.append(DataElement.string(
            tag: .mappingResource,
            vr: .CS,
            value: mappingResource
        ))
        
        let sequenceItem = SequenceItem(elements: elements)
        return createSequenceElement(tag: .contentTemplateSequence, items: [sequenceItem])
    }
    
    // MARK: - Content Sequence Creation
    
    /// Creates a Content Sequence element from content items
    private func createContentSequenceElement(items: [AnyContentItem]) throws -> DataElement {
        var sequenceItems: [SequenceItem] = []
        
        for item in items {
            let sequenceItem = try createContentItemSequenceItem(item: item)
            sequenceItems.append(sequenceItem)
        }
        
        return createSequenceElement(tag: .contentSequence, items: sequenceItems)
    }
    
    /// Creates a sequence item for a content item
    private func createContentItemSequenceItem(item: AnyContentItem) throws -> SequenceItem {
        var elements: [DataElement] = []
        
        // Value Type (0040,A040)
        elements.append(DataElement.string(
            tag: .valueType,
            vr: .CS,
            value: item.valueType.rawValue
        ))
        
        // Relationship Type (0040,A010)
        if let relationshipType = item.relationshipType {
            elements.append(DataElement.string(
                tag: .relationshipType,
                vr: .CS,
                value: relationshipType.rawValue
            ))
        }
        
        // Concept Name Code Sequence (0040,A043)
        if let conceptName = item.conceptName {
            elements.append(try createCodeSequenceElement(
                tag: .conceptNameCodeSequence,
                code: conceptName
            ))
        }
        
        // Observation DateTime (0040,A032)
        if let observationDateTime = item.observationDateTime {
            elements.append(DataElement.string(
                tag: .observationDateTime,
                vr: .DT,
                value: observationDateTime
            ))
        }
        
        // Value type-specific elements
        try addValueTypeSpecificElements(to: &elements, item: item)

        // Content Sequence (0040,A730) of a non-CONTAINER item: the Document Relationship
        // Macro (PS3.3 Table C.17-6) applies to every content item, so children of a CODE,
        // NUM, IMAGE, SCOORD, ... item are nested inside it (Type 1C: present only when the
        // item has relationships). CONTAINER writes its own in addContainerElements.
        if !item.isContainer, !item.contentItems.isEmpty {
            elements.append(try createContentSequenceElement(items: item.contentItems))
        }

        return SequenceItem(elements: elements)
    }
    
    /// Adds value type-specific elements to a content item
    private func addValueTypeSpecificElements(to elements: inout [DataElement], item: AnyContentItem) throws {
        switch item.valueType {
        case .text:
            if let textItem = item.asText {
                elements.append(DataElement.string(
                    tag: .textValue,
                    vr: .UT,
                    value: textItem.textValue
                ))
            }
            
        case .code:
            if let codeItem = item.asCode {
                elements.append(try createCodeSequenceElement(
                    tag: .conceptCodeSequence,
                    code: codeItem.conceptCode
                ))
            }
            
        case .num:
            if let numericItem = item.asNumeric {
                try addNumericElements(to: &elements, item: numericItem)
            }
            
        case .date:
            if let dateItem = item.asDate {
                elements.append(DataElement.string(
                    tag: .date,
                    vr: .DA,
                    value: dateItem.dateValue
                ))
            }
            
        case .time:
            if let timeItem = item.asTime {
                elements.append(DataElement.string(
                    tag: .time,
                    vr: .TM,
                    value: timeItem.timeValue
                ))
            }
            
        case .datetime:
            if let dateTimeItem = item.asDateTime {
                elements.append(DataElement.string(
                    tag: .dateTime,
                    vr: .DT,
                    value: dateTimeItem.dateTimeValue
                ))
            }
            
        case .pname:
            if let personNameItem = item.asPersonName {
                elements.append(DataElement.string(
                    tag: .personName,
                    vr: .PN,
                    value: personNameItem.personName
                ))
            }
            
        case .uidref:
            if let uidRefItem = item.asUIDRef {
                elements.append(DataElement.string(
                    tag: .uid,
                    vr: .UI,
                    value: uidRefItem.uidValue
                ))
            }
            
        case .composite:
            if let compositeItem = item.asComposite {
                elements.append(createReferencedSOPSequenceElement(
                    sopClassUID: compositeItem.referencedSOPSequence.sopClassUID,
                    sopInstanceUID: compositeItem.referencedSOPSequence.sopInstanceUID
                ))
            }
            
        case .image:
            if let imageItem = item.asImage {
                elements.append(createImageReferencedSOPSequenceElement(imageItem: imageItem))
            }
            
        case .waveform:
            if let waveformItem = item.asWaveform {
                elements.append(createWaveformReferencedSOPSequenceElement(waveformItem: waveformItem))
            }
            
        case .scoord:
            if let scoordItem = item.asSpatialCoordinates {
                addSpatialCoordinatesElements(to: &elements, item: scoordItem)
            }
            
        case .scoord3D:
            if let scoord3DItem = item.asSpatialCoordinates3D {
                addSpatialCoordinates3DElements(to: &elements, item: scoord3DItem)
            }
            
        case .tcoord:
            if let tcoordItem = item.asTemporalCoordinates {
                addTemporalCoordinatesElements(to: &elements, item: tcoordItem)
            }
            
        case .container:
            if let containerItem = item.asContainer {
                try addContainerElements(to: &elements, item: containerItem)
            }

        case .table:
            if let tableItem = item.asTable {
                try addTableElements(to: &elements, item: tableItem)
            }
        }
    }

    // MARK: - Table Content Item Elements (PS3.3 C.18.10)

    /// Writes the Tabulated Values Sequence (0040,A801) of a TABLE content item.
    private func addTableElements(to elements: inout [DataElement], item: TableContentItem) throws {
        var table: [DataElement] = [
            DataElement.uint32(tag: .numberOfTableRows, value: UInt32(item.rows)),
            DataElement.uint32(tag: .numberOfTableColumns, value: UInt32(item.columns)),
        ]
        if !item.rowDefinitions.isEmpty {
            table.append(createSequenceElement(tag: .tableRowDefinitionSequence,
                items: try item.rowDefinitions.map { try axisItem($0, numberTag: .tableRowNumber) }))
        }
        if !item.columnDefinitions.isEmpty {
            table.append(createSequenceElement(tag: .tableColumnDefinitionSequence,
                items: try item.columnDefinitions.map { try axisItem($0, numberTag: .tableColumnNumber) }))
        }
        table.append(createSequenceElement(tag: .cellValuesSequence, items: try item.cells.map(cellItem)))
        elements.append(createSequenceElement(tag: .tabulatedValuesSequence, items: [SequenceItem(elements: table)]))
    }

    private func axisItem(_ def: TableContentItem.TableAxisDefinition, numberTag: Tag) throws -> SequenceItem {
        var els: [DataElement] = []
        if let index = def.index { els.append(DataElement.uint32(tag: numberTag, value: UInt32(index))) }
        els.append(try createCodeSequenceElement(tag: .conceptNameCodeSequence, code: def.concept))
        if let units = def.units { els.append(try createCodeSequenceElement(tag: .measurementUnitsCodeSequence, code: units)) }
        return SequenceItem(elements: els)
    }

    private func cellItem(_ cell: TableContentItem.TableCell) throws -> SequenceItem {
        var els: [DataElement] = []
        if let row = cell.row { els.append(DataElement.uint32(tag: .tableRowNumber, value: UInt32(row))) }
        if let column = cell.column { els.append(DataElement.uint32(tag: .tableColumnNumber, value: UInt32(column))) }
        // Selector Attribute VR (0072,0050), Type 1C: names the Selector <VR> Value attribute
        // that carries the cell (Table C.18.10-1). Integer cells are IS unless a value lies
        // outside the IS range, in which case they are SV (see `integerSelectorVR`).
        let selectorVR: VR?
        if case .integer(let values) = cell.value {
            selectorVR = Self.integerSelectorVR(values)
        } else {
            selectorVR = cell.value.selectorVR
        }
        if let vr = selectorVR {
            els.append(DataElement.string(tag: .selectorAttributeVR, vr: .CS, value: vr.rawValue))
        }
        switch cell.value {
        case .text(let values):
            els.append(DataElement.strings(tag: .selectorUCValue, vr: .UC, values: values))
        case .decimal(let values):
            els.append(DataElement.strings(tag: .selectorDSValue, vr: .DS, values: values.map { formatDecimalString($0) }))
        case .floatingPoint(let values):
            els.append(DataElement.float64s(tag: .selectorFDValue, values: values))
        case .integer(let values):
            if selectorVR == .SV {
                // Selector SV Value (0072,0082), VR SV: 64-bit signed integers, little endian
                var data = Data(capacity: values.count * 8)
                for value in values {
                    var le = value.littleEndian
                    withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
                }
                els.append(DataElement(tag: .selectorSVValue, vr: .SV, length: UInt32(data.count), valueData: data))
            } else {
                // Selector IS Value (0072,0064), VR IS
                els.append(DataElement.strings(tag: .selectorISValue, vr: .IS, values: values.map { String($0) }))
            }
        case .dateTime(let values):
            els.append(DataElement.strings(tag: .selectorDTValue, vr: .DT, values: values))
        case .code(let codes):
            els.append(createSequenceElement(tag: .conceptCodeSequence, items: codes.map { createCodeSequenceItem(code: $0) }))
        case .contentItemReference(let ids):
            els.append(DataElement.uint32s(tag: .referencedContentItemIdentifier, values: ids.map { UInt32($0) }))
        case .absent:
            break
        }
        if let units = cell.units { els.append(try createCodeSequenceElement(tag: .measurementUnitsCodeSequence, code: units)) }
        if let qualifier = cell.qualifier { els.append(try createCodeSequenceElement(tag: .numericValueQualifierCodeSequence, code: qualifier)) }
        return SequenceItem(elements: els)
    }
    
    /// The Selector Attribute VR for an integer TABLE cell: IS while every value fits the
    /// IS range of PS3.5 Table 6.2-1 (-2^31 ... 2^31-1), otherwise SV. The model keeps every
    /// integer VR read from a file (IS, SL, SS, UL, US, SV, UV) as `Int64`, so a re-encoded
    /// table carries the same values in IS or SV.
    static func integerSelectorVR(_ values: [Int64]) -> VR {
        let fitsIS = values.allSatisfy { $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) }
        return fitsIS ? .IS : .SV
    }

    // MARK: - Numeric Content Item Elements
    
    /// Adds numeric content item elements using Measured Value Sequence
    private func addNumericElements(to elements: inout [DataElement], item: NumericContentItem) throws {
        // Numeric Value Qualifier Code Sequence (0040,A301), Type 1C (PS3.3 2026a Table
        // C.18.1-1): "Qualification of Numeric Value ... or reason for absence of Measured
        // Value Sequence (0040,A300) Item", one Item from CID 42; "Required if Measured
        // Value Sequence (0040,A300) is empty"
        if let qualifier = item.numericValueQualifier {
            elements.append(try createCodeSequenceElement(
                tag: .numericValueQualifierCodeSequence,
                code: qualifier.code.concept
            ))
        }

        // Measured Value Sequence (0040,A300), Type 2, "Zero or one Item": with no value
        // (unknown, missing, or a measurement / calculation failure, C.18.1) the Sequence
        // is written empty, "neither the value nor the units will be sent"
        guard !item.numericValues.isEmpty else {
            elements.append(createSequenceElement(tag: .measuredValueSequence, items: []))
            return
        }

        // Create Measured Value Sequence
        var measuredValueElements: [DataElement] = []
        
        // Numeric Value (0040,A30A) - as DS (Decimal String)
        let numericString = item.numericValues.map { formatDecimalString($0) }.joined(separator: "\\")
        measuredValueElements.append(DataElement.string(
            tag: .numericValue,
            vr: .DS,
            value: numericString
        ))
        
        // Measurement Units Code Sequence (0040,08EA)
        if let units = item.measurementUnits {
            measuredValueElements.append(try createCodeSequenceElement(
                tag: .measurementUnitsCodeSequence,
                code: units
            ))
        }
        
        // Floating Point Value (0040,A161) - optional high precision values
        if let floatValues = item.floatingPointValues {
            let writer = DICOMWriter()
            let float64Data = writer.serializeFloat64s(floatValues)
            measuredValueElements.append(DataElement(
                tag: .floatingPointValue,
                vr: .FD,
                length: UInt32(float64Data.count),
                valueData: float64Data
            ))
        }
        
        let measuredValueItem = SequenceItem(elements: measuredValueElements)
        elements.append(createSequenceElement(tag: .measuredValueSequence, items: [measuredValueItem]))
    }
    
    /// Formats a Double as a DICOM Decimal String
    private func formatDecimalString(_ value: Double) -> String {
        // DICOM DS allows up to 16 characters
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            // Use a reasonable precision
            let formatted = String(format: "%.10g", value)
            return formatted
        }
    }
    
    // MARK: - Referenced SOP Sequence Elements
    
    /// Creates a Referenced SOP Sequence element
    private func createReferencedSOPSequenceElement(sopClassUID: String, sopInstanceUID: String) -> DataElement {
        var elements: [DataElement] = []
        
        elements.append(DataElement.string(
            tag: .referencedSOPClassUID,
            vr: .UI,
            value: sopClassUID
        ))
        
        elements.append(DataElement.string(
            tag: .referencedSOPInstanceUID,
            vr: .UI,
            value: sopInstanceUID
        ))
        
        let sequenceItem = SequenceItem(elements: elements)
        return createSequenceElement(tag: .referencedSOPSequence, items: [sequenceItem])
    }
    
    /// Creates a Referenced SOP Sequence element for an image reference
    private func createImageReferencedSOPSequenceElement(imageItem: ImageContentItem) -> DataElement {
        var elements: [DataElement] = []
        
        elements.append(DataElement.string(
            tag: .referencedSOPClassUID,
            vr: .UI,
            value: imageItem.imageReference.sopReference.sopClassUID
        ))
        
        elements.append(DataElement.string(
            tag: .referencedSOPInstanceUID,
            vr: .UI,
            value: imageItem.imageReference.sopReference.sopInstanceUID
        ))
        
        // Referenced Frame Number (0008,1160)
        if let frameNumbers = imageItem.imageReference.frameNumbers, !frameNumbers.isEmpty {
            let frameString = frameNumbers.map { String($0) }.joined(separator: "\\")
            elements.append(DataElement.string(
                tag: .referencedFrameNumber,
                vr: .IS,
                value: frameString
            ))
        }
        
        // Referenced Segment Number (0062,000B)
        if let segmentNumbers = imageItem.imageReference.segmentNumbers, !segmentNumbers.isEmpty {
            let writer = DICOMWriter()
            let values = segmentNumbers.map { UInt16($0) }
            let segmentData = writer.serializeUInt16s(values)
            elements.append(DataElement(
                tag: .referencedSegmentNumber,
                vr: .US,
                length: UInt32(segmentData.count),
                valueData: segmentData
            ))
        }
        
        let sequenceItem = SequenceItem(elements: elements)
        return createSequenceElement(tag: .referencedSOPSequence, items: [sequenceItem])
    }
    
    /// Creates a Referenced SOP Sequence element for a waveform reference
    private func createWaveformReferencedSOPSequenceElement(waveformItem: WaveformContentItem) -> DataElement {
        var elements: [DataElement] = []
        
        elements.append(DataElement.string(
            tag: .referencedSOPClassUID,
            vr: .UI,
            value: waveformItem.waveformReference.sopReference.sopClassUID
        ))
        
        elements.append(DataElement.string(
            tag: .referencedSOPInstanceUID,
            vr: .UI,
            value: waveformItem.waveformReference.sopReference.sopInstanceUID
        ))
        
        // Referenced Waveform Channels (0040,A0B0), US, Type 1C (PS3.3 2026a Table
        // C.18.5-1): the (M,C) pairs of C.18.5.1.1, written since 2026-10-01 (D196)
        if let channels = waveformItem.waveformReference.referencedChannels, !channels.isEmpty {
            let values = channels.flatMap { [UInt16(clamping: $0.multiplexGroup), UInt16(clamping: $0.channel)] }
            let data = DICOMWriter().serializeUInt16s(values)
            elements.append(DataElement(
                tag: Self.referencedWaveformChannelsTag,
                vr: .US,
                length: UInt32(data.count),
                valueData: data
            ))
        }
        
        let sequenceItem = SequenceItem(elements: elements)
        return createSequenceElement(tag: .referencedSOPSequence, items: [sequenceItem])
    }
    
    // MARK: - Spatial Coordinates Elements
    
    /// Adds spatial coordinates elements
    private func addSpatialCoordinatesElements(to elements: inout [DataElement], item: SpatialCoordinatesContentItem) {
        // Graphic Type (0070,0023)
        elements.append(DataElement.string(
            tag: .graphicType,
            vr: .CS,
            value: item.graphicType.rawValue
        ))
        
        // Graphic Data (0070,0022) - FL
        let writer = DICOMWriter()
        let graphicData = writer.serializeFloat32s(item.graphicData)
        elements.append(DataElement(
            tag: .graphicData,
            vr: .FL,
            length: UInt32(graphicData.count),
            valueData: graphicData
        ))
    }
    
    /// Adds 3D spatial coordinates elements
    private func addSpatialCoordinates3DElements(to elements: inout [DataElement], item: SpatialCoordinates3DContentItem) {
        // Graphic Type (0070,0023)
        elements.append(DataElement.string(
            tag: .graphicType,
            vr: .CS,
            value: item.graphicType.rawValue
        ))
        
        // Graphic Data 3D (0070,0022) - FL
        let writer = DICOMWriter()
        let graphicData = writer.serializeFloat32s(item.graphicData)
        elements.append(DataElement(
            tag: .graphicData,
            vr: .FL,
            length: UInt32(graphicData.count),
            valueData: graphicData
        ))
        
        // Referenced Frame of Reference UID (3006,0024), Type 1 (PS3.3 Table C.18.9-1)
        if let frameOfRefUID = item.frameOfReferenceUID {
            elements.append(DataElement.string(
                tag: .referencedFrameOfReferenceUID,
                vr: .UI,
                value: frameOfRefUID
            ))
        }
    }
    
    // MARK: - Temporal Coordinates Elements
    
    /// Adds temporal coordinates elements
    private func addTemporalCoordinatesElements(to elements: inout [DataElement], item: TemporalCoordinatesContentItem) {
        // Temporal Range Type (0040,A130)
        elements.append(DataElement.string(
            tag: .temporalRangeType,
            vr: .CS,
            value: item.temporalRangeType.rawValue
        ))
        
        // Referenced Sample Positions (0040,A132) - UL
        if let samplePositions = item.referencedSamplePositions, !samplePositions.isEmpty {
            let writer = DICOMWriter()
            let samplePositionsData = writer.serializeUInt32s(samplePositions)
            elements.append(DataElement(
                tag: .referencedSamplePositions,
                vr: .UL,
                length: UInt32(samplePositionsData.count),
                valueData: samplePositionsData
            ))
        }
        
        // Referenced Time Offsets (0040,A138) - DS
        if let timeOffsets = item.referencedTimeOffsets, !timeOffsets.isEmpty {
            let timeOffsetString = timeOffsets.map { formatDecimalString($0) }.joined(separator: "\\")
            elements.append(DataElement.string(
                tag: .referencedTimeOffsets,
                vr: .DS,
                value: timeOffsetString
            ))
        }
        
        // Referenced DateTime (0040,A13A) - DT
        if let dateTimes = item.referencedDateTime, !dateTimes.isEmpty {
            let dateTimeString = dateTimes.joined(separator: "\\")
            elements.append(DataElement.string(
                tag: .referencedDateTime,
                vr: .DT,
                value: dateTimeString
            ))
        }
    }
    
    // MARK: - Container Elements
    
    /// Adds container content item elements
    private func addContainerElements(to elements: inout [DataElement], item: ContainerContentItem) throws {
        // Continuity of Content (0040,A050)
        elements.append(DataElement.string(
            tag: .continuityOfContent,
            vr: .CS,
            value: item.continuityOfContent.rawValue
        ))
        
        // Content Template Sequence (if template is specified)
        if let templateID = item.templateIdentifier {
            elements.append(createTemplateSequenceElement(
                templateIdentifier: templateID,
                mappingResource: item.mappingResource ?? "DCMR"
            ))
        }
        
        // Content Sequence (nested content items)
        if !item.contentItems.isEmpty {
            elements.append(try createContentSequenceElement(items: item.contentItems))
        }
    }
    
    // MARK: - Sequence Element Creation
    
    /// Creates a sequence element from sequence items
    private func createSequenceElement(tag: Tag, items: [SequenceItem]) -> DataElement {
        // Calculate the total length of all items
        let writer = DICOMWriter()
        var totalLength: UInt32 = 0
        
        for item in items {
            let itemData = writer.serializeSequenceItem(item)
            totalLength += UInt32(itemData.count)
        }
        
        // Create the sequence data
        var sequenceData = Data()
        for item in items {
            sequenceData.append(writer.serializeSequenceItem(item))
        }
        
        return DataElement(
            tag: tag,
            vr: .SQ,
            length: totalLength,
            valueData: sequenceData,
            sequenceItems: items
        )
    }
}

// MARK: - SRDocument Extension for Serialization

extension SRDocument {
    /// Converts this SR document to a DICOM DataSet
    /// - Returns: A DICOM DataSet representation of this document
    /// - Throws: `SRDocumentSerializer.SerializationError` if serialization fails
    public func toDataSet() throws -> DataSet {
        let serializer = SRDocumentSerializer()
        return try serializer.serialize(document: self)
    }
}

// MARK: - Tag Extensions for SR Serialization
// Note: Temporal Range Type, Referenced Sample Positions, Referenced Time Offsets and
// Referenced DateTime (DICOMCore Tag+Waveforms.swift) and Graphic Type / Graphic Data
// (DICOMCore Tag+PresentationState.swift) are defined by DICOMCore, which DICOMKit
// re-exports; the copies this file carried made `Tag.referencedSamplePositions` ambiguous
// for code importing both modules and were removed 2026-09-29.

extension Tag {
    /// Performed Procedure Code Sequence (0040,A372)
    /// VR: SQ, VM: 1 — Type 2 in the SR Document General Module (PS3.3 Table C.17-2)
    public static let performedProcedureCodeSequence = Tag(group: 0x0040, element: 0xA372)
}
