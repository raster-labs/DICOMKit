// NEMA-verified: 2026a, checked 2026-09-29 — value-type rules delegate to DICOMCore allows(_:), which reproduces PS3.3 2026a Tables A.35.x-2 (D16); validation recurses into the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31)
/// DICOM Structured Reporting Document Builder
///
/// Provides a fluent API for creating valid DICOM SR documents programmatically.
///
/// Reference: PS3.3 Section C.17 - SR Document Information Object Definitions

import Foundation
import DICOMCore

/// Builder for creating DICOM Structured Reporting documents
///
/// Example:
/// ```swift
/// let document = try SRDocumentBuilder(documentType: .comprehensiveSR)
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle(CodedConcept.measurementReport)
///     .addText(conceptName: .finding, value: "Normal appearance")
///     .addNumeric(conceptName: .measurement, value: 42.5, units: .millimeter)
///     .build()
/// ```
public struct SRDocumentBuilder: Sendable {
    
    // MARK: - Configuration
    
    /// The SR document type being built
    public let documentType: SRDocumentType
    
    /// Whether to validate during build
    public let validateOnBuild: Bool
    
    // MARK: - Document Identification
    
    /// SOP Instance UID (will be generated if not set)
    public private(set) var sopInstanceUID: String?
    
    /// Study Instance UID
    public private(set) var studyInstanceUID: String?
    
    /// Series Instance UID
    public private(set) var seriesInstanceUID: String?
    
    /// Instance Number
    public private(set) var instanceNumber: String?
    
    // MARK: - Patient Information
    
    /// Patient ID
    public private(set) var patientID: String?
    
    /// Patient Name
    public private(set) var patientName: String?
    
    /// Patient Birth Date
    public private(set) var patientBirthDate: String?
    
    /// Patient Sex
    public private(set) var patientSex: String?
    
    // MARK: - Study Information
    
    /// Study Date
    public private(set) var studyDate: String?
    
    /// Study Time
    public private(set) var studyTime: String?
    
    /// Study Description
    public private(set) var studyDescription: String?
    
    /// Accession Number
    public private(set) var accessionNumber: String?
    
    /// Referring Physician's Name
    public private(set) var referringPhysicianName: String?
    
    // MARK: - Series Information
    
    /// Series Number
    public private(set) var seriesNumber: String?
    
    /// Series Description
    public private(set) var seriesDescription: String?
    
    /// Modality (defaults to "SR")
    public private(set) var modality: String = "SR"
    
    // MARK: - Document Information
    
    /// Content Date
    public private(set) var contentDate: String?
    
    /// Content Time
    public private(set) var contentTime: String?
    
    /// Document Title (Concept Name of root container)
    public private(set) var documentTitle: CodedConcept?
    
    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .partial
    
    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified
    
    /// Preliminary Flag
    public private(set) var preliminaryFlag: PreliminaryFlag?
    
    // MARK: - Content Tree
    
    /// Continuity of content for the root container
    public private(set) var continuityOfContent: ContinuityOfContent = .separate
    
    /// Template identifier for the root container
    public private(set) var templateIdentifier: String?
    
    /// Mapping resource for the template
    public private(set) var mappingResource: String?
    
    /// Root-level content items
    public private(set) var contentItems: [AnyContentItem] = []
    
    // MARK: - Initialization
    
    /// Creates a new SR document builder
    /// - Parameters:
    ///   - documentType: The type of SR document to create
    ///   - validateOnBuild: Whether to validate the document during build (default: true)
    public init(documentType: SRDocumentType = .comprehensiveSR, validateOnBuild: Bool = true) {
        self.documentType = documentType
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> SRDocumentBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> SRDocumentBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> SRDocumentBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> SRDocumentBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> SRDocumentBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> SRDocumentBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> SRDocumentBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> SRDocumentBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> SRDocumentBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> SRDocumentBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> SRDocumentBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> SRDocumentBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> SRDocumentBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> SRDocumentBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> SRDocumentBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    /// Sets the Modality
    /// - Parameter modality: The modality (defaults to "SR")
    /// - Returns: Updated builder
    public func withModality(_ modality: String) -> SRDocumentBuilder {
        var copy = self
        copy.modality = modality
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> SRDocumentBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> SRDocumentBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title
    /// - Parameter title: The document title as a coded concept
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> SRDocumentBuilder {
        var copy = self
        copy.documentTitle = title
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> SRDocumentBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> SRDocumentBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> SRDocumentBuilder {
        var copy = self
        copy.preliminaryFlag = flag
        return copy
    }
    
    /// Sets the Continuity of Content for the root container
    /// - Parameter continuity: The continuity of content
    /// - Returns: Updated builder
    public func withContinuityOfContent(_ continuity: ContinuityOfContent) -> SRDocumentBuilder {
        var copy = self
        copy.continuityOfContent = continuity
        return copy
    }
    
    /// Sets the Template Identifier
    /// - Parameters:
    ///   - identifier: The template identifier (TID)
    ///   - mappingResource: The mapping resource (default: "DCMR")
    /// - Returns: Updated builder
    public func withTemplate(identifier: String, mappingResource: String = "DCMR") -> SRDocumentBuilder {
        var copy = self
        copy.templateIdentifier = identifier
        copy.mappingResource = mappingResource
        return copy
    }
    
    // MARK: - Content Item Addition
    
    /// Adds a text content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The text value
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addText(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a code content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The coded value
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addCode(
        conceptName: CodedConcept? = nil,
        value: CodedConcept,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a numeric content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The numeric value
    ///   - units: The measurement units
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a numeric content item with multiple values
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: values,
            units: units,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a date content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The date value in DICOM DA format (YYYYMMDD)
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addDate(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a time content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The time value in DICOM TM format
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addTime(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a datetime content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The datetime value in DICOM DT format
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addDateTime(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a person name content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The person name in DICOM PN format
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addPersonName(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a UID reference content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The UID value
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addUIDRef(
        conceptName: CodedConcept? = nil,
        value: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(UIDRefContentItem(
            conceptName: conceptName,
            uidValue: value,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds an image reference content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced image
    ///   - sopInstanceUID: The SOP Instance UID of the referenced image
    ///   - frameNumbers: Optional frame numbers
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addImageReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a composite reference content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced object
    ///   - sopInstanceUID: The SOP Instance UID of the referenced object
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addCompositeReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CompositeContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a waveform reference content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced waveform
    ///   - sopInstanceUID: The SOP Instance UID of the referenced waveform
    ///   - channelNumbers: Optional channel numbers
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addWaveformReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        channelNumbers: [Int]? = nil,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        let waveformRef = WaveformReference(
            sopReference: ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID),
            channelNumbers: channelNumbers
        )
        copy.contentItems.append(AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds 2D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - graphicType: The type of graphic
    ///   - graphicData: The coordinate data as [col1, row1, col2, row2, ...]
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addSpatialCoordinates(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType,
        graphicData: [Float],
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(SpatialCoordinatesContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds 3D spatial coordinates content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - graphicType: The type of graphic
    ///   - graphicData: The coordinate data as [x1, y1, z1, x2, y2, z2, ...]
    ///   - frameOfReferenceUID: The Frame of Reference UID
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addSpatialCoordinates3D(
        conceptName: CodedConcept? = nil,
        graphicType: GraphicType3D,
        graphicData: [Float],
        frameOfReferenceUID: String? = nil,
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(SpatialCoordinates3DContentItem(
            conceptName: conceptName,
            graphicType: graphicType,
            graphicData: graphicData,
            frameOfReferenceUID: frameOfReferenceUID,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds temporal coordinates content item with sample positions
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - temporalRangeType: The type of temporal range
    ///   - samplePositions: Sample positions for waveform data
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addTemporalCoordinates(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        samplePositions: [UInt32],
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            samplePositions: samplePositions,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds temporal coordinates content item with time offsets
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - temporalRangeType: The type of temporal range
    ///   - timeOffsets: Time offsets in seconds
    ///   - relationshipType: The relationship to the parent (default: .contains)
    /// - Returns: Updated builder
    public func addTemporalCoordinatesWithTimeOffsets(
        conceptName: CodedConcept? = nil,
        temporalRangeType: TemporalRangeType,
        timeOffsets: [Double],
        relationshipType: RelationshipType = .contains
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TemporalCoordinatesContentItem(
            conceptName: conceptName,
            temporalRangeType: temporalRangeType,
            timeOffsets: timeOffsets,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a container content item with nested items
    /// - Parameters:
    ///   - conceptName: The concept name for this container
    ///   - continuityOfContent: The continuity of content (default: .separate)
    ///   - relationshipType: The relationship to the parent (default: .contains)
    ///   - templateIdentifier: Optional template identifier
    ///   - builder: A closure that builds the container's content items
    /// - Returns: Updated builder
    public func addContainer(
        conceptName: CodedConcept? = nil,
        continuityOfContent: ContinuityOfContent = .separate,
        relationshipType: RelationshipType = .contains,
        templateIdentifier: String? = nil,
        @ContainerBuilder builder: () -> [AnyContentItem]
    ) -> SRDocumentBuilder {
        var copy = self
        let items = builder()
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuityOfContent,
            contentItems: items,
            templateIdentifier: templateIdentifier,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a container content item with pre-built items
    /// - Parameters:
    ///   - conceptName: The concept name for this container
    ///   - continuityOfContent: The continuity of content (default: .separate)
    ///   - relationshipType: The relationship to the parent (default: .contains)
    ///   - templateIdentifier: Optional template identifier
    ///   - items: The content items to include in the container
    /// - Returns: Updated builder
    public func addContainer(
        conceptName: CodedConcept? = nil,
        continuityOfContent: ContinuityOfContent = .separate,
        relationshipType: RelationshipType = .contains,
        templateIdentifier: String? = nil,
        items: [AnyContentItem]
    ) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: continuityOfContent,
            contentItems: items,
            templateIdentifier: templateIdentifier,
            relationshipType: relationshipType
        )))
        return copy
    }
    
    /// Adds a pre-built content item
    /// - Parameter item: The content item to add
    /// - Returns: Updated builder
    public func addItem(_ item: AnyContentItem) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(item)
        return copy
    }
    
    /// Adds multiple pre-built content items
    /// - Parameter items: The content items to add
    /// - Returns: Updated builder
    public func addItems(_ items: [AnyContentItem]) -> SRDocumentBuilder {
        var copy = self
        copy.contentItems.append(contentsOf: items)
        return copy
    }
    
    // MARK: - Build
    
    /// Builds the SR document
    /// - Returns: The constructed SR document
    /// - Throws: `BuildError` if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided.
        // Note: Auto-generated UIDs use UIDGenerator with the default UID root (UIDGenerator.defaultRoot).
        // In production environments with specific UID root requirements, developers should
        // provide their own UIDs using withSOPInstanceUID(), withStudyInstanceUID(), and
        // withSeriesInstanceUID() methods to ensure compliance with organizational policies.
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        
        // Create the root container
        let rootContent = ContainerContentItem(
            conceptName: documentTitle,
            continuityOfContent: continuityOfContent,
            contentItems: contentItems,
            templateIdentifier: templateIdentifier,
            mappingResource: mappingResource
        )
        
        return SRDocument(
            sopClassUID: documentType.sopClassUID,
            sopInstanceUID: finalSOPInstanceUID,
            patientID: patientID,
            patientName: patientName,
            studyInstanceUID: finalStudyInstanceUID,
            studyDate: studyDate,
            studyTime: studyTime,
            accessionNumber: accessionNumber,
            seriesInstanceUID: finalSeriesInstanceUID,
            seriesNumber: seriesNumber,
            modality: modality,
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: instanceNumber,
            completionFlag: completionFlag,
            verificationFlag: verificationFlag,
            preliminaryFlag: preliminaryFlag,
            documentTitle: documentTitle,
            rootContent: rootContent,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName
        )
    }
    
    // MARK: - Validation
    
    /// Validation errors
    public enum BuildError: Error, Sendable, Equatable {
        /// Missing required patient information
        case missingPatientID
        
        /// Missing required study information
        case missingStudyInstanceUID
        
        /// Missing required document title
        case missingDocumentTitle
        
        /// Empty document (no content items)
        case emptyDocument
        
        /// Invalid value type for document type
        case invalidValueType(valueType: ContentItemValueType, documentType: SRDocumentType)
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Check for value type compatibility with document type
        try validateValueTypes(items: contentItems)
    }
    
    /// Validates that all content items use value types compatible with the document type
    private func validateValueTypes(items: [AnyContentItem]) throws {
        for item in items {
            // Check if value type is allowed for this document type
            if !documentType.allows(item.valueType) {
                throw BuildError.invalidValueType(valueType: item.valueType, documentType: documentType)
            }
            
            // Recursively validate children: a CONTAINER's, and the Content Sequence
            // any other value type may carry (PS3.3 Table C.17-6)
            try validateValueTypes(items: item.contentItems)
        }
    }
}

// MARK: - Container Builder

/// Result builder for constructing container content items
@resultBuilder
public struct ContainerBuilder {
    /// Builds an empty block
    public static func buildBlock() -> [AnyContentItem] {
        []
    }
    
    /// Builds a block from variadic content items
    public static func buildBlock(_ components: AnyContentItem...) -> [AnyContentItem] {
        components
    }
    
    /// Builds a block from arrays of content items
    public static func buildArray(_ components: [[AnyContentItem]]) -> [AnyContentItem] {
        components.flatMap { $0 }
    }
    
    public static func buildOptional(_ component: [AnyContentItem]?) -> [AnyContentItem] {
        component ?? []
    }
    
    public static func buildEither(first component: [AnyContentItem]) -> [AnyContentItem] {
        component
    }
    
    public static func buildEither(second component: [AnyContentItem]) -> [AnyContentItem] {
        component
    }
}

// MARK: - SRDocumentType Value Type Validation

extension SRDocumentType {
    /// Checks if this document type allows the specified value type.
    ///
    /// The Value Type constraints of each SR IOD (PS3.3 Tables A.35.x-2) are carried once,
    /// by ``SRDocumentType/allows(_:)`` in DICOMCore; this is the same answer.
    @available(*, deprecated, renamed: "allows(_:)")
    public func allowsValueType(_ valueType: ContentItemValueType) -> Bool {
        allows(valueType)
    }
}
