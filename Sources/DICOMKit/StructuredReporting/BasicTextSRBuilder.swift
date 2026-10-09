// NEMA-verified: 2026a, checked 2026-09-29 — DCM section concepts diffed by Scripts/diff_kit.py against PS3.16 2026a Table D-1 (121074 Recommendations); comparison against Table D-1 111424, CID 6052 and TID 3318 row 1; validation recurses into the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31)
/// Basic Text SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Basic Text SR documents.
/// Basic Text SR is the simplest structured report type, supporting text-based
/// reports with section headings and minimal coding requirements.
///
/// Reference: PS3.3 Section A.35.1 - Basic Text SR
/// Reference: PS3.4 Annex B - Storage Service Class (Basic Text SR)

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Basic Text SR documents
///
/// BasicTextSRBuilder provides a simplified API for creating text-based structured reports.
/// Basic Text SR documents are ideal for simple narrative reports with hierarchical
/// sections and minimal structured coding requirements.
///
/// Example:
/// ```swift
/// let document = try BasicTextSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle("Radiology Report")
///     .addSection("Findings") { section in
///         section.addText("Normal chest appearance with no acute findings.")
///     }
///     .addSection("Impression") { section in
///         section.addText("No significant abnormalities.")
///     }
///     .build()
/// ```
///
/// ## Supported Value Types
/// Basic Text SR supports the following value types:
/// - TEXT - Free-form text content
/// - CODE - Coded concept values
/// - DATETIME, DATE, TIME - Temporal values
/// - UIDREF - UID reference values
/// - PNAME - Person name values
/// - COMPOSITE, IMAGE - Reference types
/// - CONTAINER - For hierarchical structure
///
/// Note: NUM (numeric), SCOORD (spatial coordinates), SCOORD3D, TCOORD, and WAVEFORM
/// are NOT supported in Basic Text SR. Use `EnhancedSRBuilder` or `SRDocumentBuilder`
/// with `.comprehensiveSR` for reports requiring measurements.
public struct BasicTextSRBuilder: Sendable {
    
    // MARK: - Configuration
    
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
    
    // MARK: - Document Information
    
    /// Content Date
    public private(set) var contentDate: String?
    
    /// Content Time
    public private(set) var contentTime: String?
    
    /// Document Title (Concept Name of root container)
    public private(set) var documentTitle: CodedConcept?
    
    /// Simple string document title (converted to coded concept)
    public private(set) var documentTitleString: String?
    
    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .partial
    
    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified
    
    /// Preliminary Flag
    public private(set) var preliminaryFlag: PreliminaryFlag?
    
    // MARK: - Content Tree
    
    /// Root-level content items (sections and text)
    public private(set) var contentItems: [AnyContentItem] = []
    
    // MARK: - Initialization
    
    /// Creates a new Basic Text SR document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> BasicTextSRBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> BasicTextSRBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> BasicTextSRBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> BasicTextSRBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> BasicTextSRBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> BasicTextSRBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> BasicTextSRBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> BasicTextSRBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> BasicTextSRBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> BasicTextSRBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> BasicTextSRBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> BasicTextSRBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> BasicTextSRBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> BasicTextSRBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> BasicTextSRBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title using a coded concept
    /// - Parameter title: The document title as a coded concept
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> BasicTextSRBuilder {
        var copy = self
        copy.documentTitle = title
        copy.documentTitleString = nil
        return copy
    }
    
    /// Sets the Document Title using a simple string
    ///
    /// This method creates a coded concept using the code "121060" (Document Title)
    /// from the DCM coding scheme with your provided text as the code meaning.
    ///
    /// - Parameter title: The document title as a simple string
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: String) -> BasicTextSRBuilder {
        var copy = self
        copy.documentTitleString = title
        copy.documentTitle = nil
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> BasicTextSRBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> BasicTextSRBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> BasicTextSRBuilder {
        var copy = self
        copy.preliminaryFlag = flag
        return copy
    }
    
    // MARK: - Content Addition - Text
    
    /// Adds a text content item at the root level
    /// - Parameters:
    ///   - value: The text value
    ///   - conceptName: Optional concept name for the text item
    /// - Returns: Updated builder
    public func addText(_ value: String, conceptName: CodedConcept? = nil) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a labeled text content item (text with a string label)
    /// - Parameters:
    ///   - label: The label for the text (used as code meaning)
    ///   - value: The text value
    /// - Returns: Updated builder
    public func addLabeledText(label: String, value: String) -> BasicTextSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addText(value, conceptName: conceptName)
    }
    
    // MARK: - Content Addition - Sections
    
    /// Adds a section (container) with nested content
    ///
    /// Sections provide hierarchical organization for Basic Text SR documents.
    /// Each section can contain text, codes, and nested subsections.
    ///
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - builder: A closure that builds the section's content using a SectionBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: CodedConcept,
        @SectionContentBuilder builder: () -> [AnyContentItem]
    ) -> BasicTextSRBuilder {
        var copy = self
        let items = builder()
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a section with a string title
    ///
    /// This method creates a section with a coded concept using the string as the code meaning.
    ///
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - builder: A closure that builds the section's content using a SectionBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: String,
        @SectionContentBuilder builder: () -> [AnyContentItem]
    ) -> BasicTextSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, builder: builder)
    }
    
    /// Adds a section with pre-built content items
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - items: The content items for the section
    /// - Returns: Updated builder
    public func addSection(_ title: CodedConcept, items: [AnyContentItem]) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a section with a string title and pre-built content items
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - items: The content items for the section
    /// - Returns: Updated builder
    public func addSection(_ title: String, items: [AnyContentItem]) -> BasicTextSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, items: items)
    }
    
    // MARK: - Content Addition - Codes
    
    /// Adds a code content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The coded value
    /// - Returns: Updated builder
    public func addCode(conceptName: CodedConcept?, value: CodedConcept) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: .contains
        )))
        return copy
    }
    
    // MARK: - Content Addition - References
    
    /// Adds a person name content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - name: The person name in DICOM PN format
    /// - Returns: Updated builder
    public func addPersonName(conceptName: CodedConcept? = nil, name: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: name,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a UID reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - uid: The UID value
    /// - Returns: Updated builder
    public func addUIDRef(conceptName: CodedConcept? = nil, uid: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(UIDRefContentItem(
            conceptName: conceptName,
            uidValue: uid,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a date content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - date: The date value in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func addDate(conceptName: CodedConcept? = nil, date: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: date,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a time content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - time: The time value in DICOM TM format
    /// - Returns: Updated builder
    public func addTime(conceptName: CodedConcept? = nil, time: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: time,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a datetime content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - datetime: The datetime value in DICOM DT format
    /// - Returns: Updated builder
    public func addDateTime(conceptName: CodedConcept? = nil, datetime: String) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: datetime,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds an image reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced image
    ///   - sopInstanceUID: The SOP Instance UID of the referenced image
    ///   - frameNumbers: Optional frame numbers
    /// - Returns: Updated builder
    public func addImageReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a pre-built content item
    /// - Parameter item: The content item to add
    /// - Returns: Updated builder
    public func addItem(_ item: AnyContentItem) -> BasicTextSRBuilder {
        var copy = self
        copy.contentItems.append(item)
        return copy
    }
    
    // MARK: - Common Report Sections
    
    /// Adds a "Findings" section with text content
    /// - Parameter text: The findings text
    /// - Returns: Updated builder
    public func addFindings(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.findings) {
            SectionContent.text(text)
        }
    }
    
    /// Adds an "Impression" section with text content
    /// - Parameter text: The impression text
    /// - Returns: Updated builder
    public func addImpression(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.impression) {
            SectionContent.text(text)
        }
    }
    
    /// Adds a "Clinical History" section with text content
    /// - Parameter text: The clinical history text
    /// - Returns: Updated builder
    public func addClinicalHistory(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.clinicalHistory) {
            SectionContent.text(text)
        }
    }
    
    /// Adds a "Conclusion" section with text content
    /// - Parameter text: The conclusion text
    /// - Returns: Updated builder
    public func addConclusion(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.conclusion) {
            SectionContent.text(text)
        }
    }
    
    /// Adds a "Recommendation" section with text content
    /// - Parameter text: The recommendation text
    /// - Returns: Updated builder
    public func addRecommendation(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.recommendation) {
            SectionContent.text(text)
        }
    }
    
    /// Adds a "Procedure Description" section with text content
    /// - Parameter text: The procedure description text
    /// - Returns: Updated builder
    public func addProcedureDescription(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.procedureDescription) {
            SectionContent.text(text)
        }
    }
    
    /// Adds a "Comparison" section with text content
    /// - Parameter text: The comparison text
    /// - Returns: Updated builder
    public func addComparison(_ text: String) -> BasicTextSRBuilder {
        addSection(CodedConcept.comparison) {
            SectionContent.text(text)
        }
    }
    
    // MARK: - Build
    
    /// Builds the Basic Text SR document
    /// - Returns: The constructed SR document
    /// - Throws: `BuildError` if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided.
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        
        // Determine document title
        let finalDocumentTitle: CodedConcept?
        if let title = documentTitle {
            finalDocumentTitle = title
        } else if let titleString = documentTitleString {
            finalDocumentTitle = CodedConcept.documentTitle(titleString)
        } else {
            finalDocumentTitle = nil
        }
        
        // Create the root container
        let rootContent = ContainerContentItem(
            conceptName: finalDocumentTitle,
            continuityOfContent: .separate,
            contentItems: contentItems
        )
        
        return SRDocument(
            sopClassUID: SRDocumentType.basicTextSR.sopClassUID,
            sopInstanceUID: finalSOPInstanceUID,
            patientID: patientID,
            patientName: patientName,
            studyInstanceUID: finalStudyInstanceUID,
            studyDate: studyDate,
            studyTime: studyTime,
            accessionNumber: accessionNumber,
            seriesInstanceUID: finalSeriesInstanceUID,
            seriesNumber: seriesNumber,
            modality: "SR",
            contentDate: contentDate,
            contentTime: contentTime,
            instanceNumber: instanceNumber,
            completionFlag: completionFlag,
            verificationFlag: verificationFlag,
            preliminaryFlag: preliminaryFlag,
            documentTitle: finalDocumentTitle,
            rootContent: rootContent,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName
        )
    }
    
    // MARK: - Validation
    
    /// Validation errors for Basic Text SR documents
    public enum BuildError: Error, Sendable, Equatable {
        /// Content item uses value type not allowed in Basic Text SR
        case unsupportedValueType(valueType: ContentItemValueType)
        
        /// Description of the error
        public var localizedDescription: String {
            switch self {
            case .unsupportedValueType(let valueType):
                return "Value type '\(valueType)' is not supported in Basic Text SR documents. Use EnhancedSRBuilder or SRDocumentBuilder for measurements."
            }
        }
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Check that all content items use value types compatible with Basic Text SR
        try validateValueTypes(items: contentItems)
    }
    
    /// Validates that all content items use value types compatible with Basic Text SR
    private func validateValueTypes(items: [AnyContentItem]) throws {
        let allowedTypes = SRDocumentType.basicTextSR.allowedValueTypes
        
        for item in items {
            if !allowedTypes.contains(item.valueType) {
                throw BuildError.unsupportedValueType(valueType: item.valueType)
            }
            
            // Recursively validate children: a CONTAINER's, and the Content Sequence
            // any other value type may carry (PS3.3 Table C.17-6)
            try validateValueTypes(items: item.contentItems)
        }
    }
}

// MARK: - Section Content Builder

/// Result builder for constructing section content items
@resultBuilder
public struct SectionContentBuilder {
    /// Builds an empty block
    public static func buildBlock() -> [AnyContentItem] {
        []
    }
    
    /// Builds a block from arrays of content items
    public static func buildBlock(_ components: [AnyContentItem]...) -> [AnyContentItem] {
        components.flatMap { $0 }
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
    
    /// Builds from an expression (single item)
    public static func buildExpression(_ expression: AnyContentItem) -> [AnyContentItem] {
        [expression]
    }
}

// MARK: - Section Content Helpers

/// Helper enum for building section content
public enum SectionContent {
    /// Creates a text content item
    /// - Parameters:
    ///   - value: The text value
    ///   - conceptName: Optional concept name
    /// - Returns: The content item
    public static func text(_ value: String, conceptName: CodedConcept? = nil) -> AnyContentItem {
        AnyContentItem(TextContentItem(
            conceptName: conceptName,
            textValue: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a labeled text content item
    /// - Parameters:
    ///   - label: The label for the text
    ///   - value: The text value
    /// - Returns: The content item
    public static func labeledText(label: String, value: String) -> AnyContentItem {
        AnyContentItem(TextContentItem(
            conceptName: CodedConcept.textLabel(label),
            textValue: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a code content item
    /// - Parameters:
    ///   - conceptName: The concept name
    ///   - value: The coded value
    /// - Returns: The content item
    public static func code(conceptName: CodedConcept?, value: CodedConcept) -> AnyContentItem {
        AnyContentItem(CodeContentItem(
            conceptName: conceptName,
            conceptCode: value,
            relationshipType: .contains
        ))
    }
    
    /// Creates a person name content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - name: The person name
    /// - Returns: The content item
    public static func personName(conceptName: CodedConcept? = nil, name: String) -> AnyContentItem {
        AnyContentItem(PersonNameContentItem(
            conceptName: conceptName,
            personName: name,
            relationshipType: .contains
        ))
    }
    
    /// Creates a date content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - date: The date value
    /// - Returns: The content item
    public static func date(conceptName: CodedConcept? = nil, date: String) -> AnyContentItem {
        AnyContentItem(DateContentItem(
            conceptName: conceptName,
            dateValue: date,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection (nested container)
    /// - Parameters:
    ///   - title: The section title
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(title: String, items: [AnyContentItem]) -> AnyContentItem {
        AnyContentItem(ContainerContentItem(
            conceptName: CodedConcept.sectionHeading(title),
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection (nested container) with a coded title
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(title: CodedConcept, items: [AnyContentItem]) -> AnyContentItem {
        AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        ))
    }
}

// MARK: - CodedConcept Extensions for Basic Text SR

extension CodedConcept {
    /// Creates a section heading coded concept from a string
    /// - Parameter title: The section title
    /// - Returns: A coded concept for the section heading
    public static func sectionHeading(_ title: String) -> CodedConcept {
        CodedConcept(
            codeValue: "121070",
            codingSchemeDesignator: "DCM",
            codeMeaning: title
        )
    }
    
    /// Creates a document title coded concept from a string
    /// - Parameter title: The document title
    /// - Returns: A coded concept for the document title
    public static func documentTitle(_ title: String) -> CodedConcept {
        CodedConcept(
            codeValue: "121060",
            codingSchemeDesignator: "DCM",
            codeMeaning: title
        )
    }
    
    /// Creates a text label coded concept from a string
    /// - Parameter label: The label text
    /// - Returns: A coded concept for the text label
    public static func textLabel(_ label: String) -> CodedConcept {
        CodedConcept(
            codeValue: "121050",
            codingSchemeDesignator: "DCM",
            codeMeaning: label
        )
    }
    
    // MARK: - Common Section Concepts
    
    /// Findings section concept
    public static let findings = CodedConcept(
        codeValue: "121070",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Findings"
    )
    
    /// Impression section concept
    public static let impression = CodedConcept(
        codeValue: "121073",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Impression"
    )
    
    /// Clinical History section concept
    public static let clinicalHistory = CodedConcept(
        codeValue: "121060",
        codingSchemeDesignator: "DCM",
        codeMeaning: "History"
    )
    
    /// Conclusion section concept
    public static let conclusion = CodedConcept(
        codeValue: "121077",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Conclusion"
    )
    
    /// Recommendations section concept
    public static let recommendation = CodedConcept(
        codeValue: "121074",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Recommendations"
    )
    
    /// Procedure Description section concept
    public static let procedureDescription = CodedConcept(
        codeValue: "121065",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Procedure Description"
    )
    
    /// Comparison section concept
    ///
    /// (111424, DCM, "Comparison to previous studies") — PS3.16 2026a CID 6052 "Breast Imaging
    /// Report Section Title" and CID 6053; the CONTAINER concept name of TID 3318 row 1.
    /// Table D-1: "The result of assessing the current imaging study in comparison to previous
    /// imaging studies." (The former value 121071 is "Finding" in Table D-1; CID 7001/7002 have no
    /// comparison heading.)
    public static let comparison = CodedConcept(
        codeValue: "111424",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Comparison to previous studies"
    )
}
