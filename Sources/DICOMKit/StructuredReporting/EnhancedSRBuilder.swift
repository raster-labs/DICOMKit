// NEMA-verified: 2026a, checked 2026-09-29 — measurement concepts are the SCT codes of PS3.16 2026a CID 7470-7472 and (126010, DCM, Imaging Measurements); validation recurses into the Content Sequence (0040,A730) of every value type per PS3.3 2026a Table C.17-6 (D31)
/// Enhanced SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Enhanced SR documents.
/// Enhanced SR extends Basic Text SR by adding support for numeric measurements (NUM),
/// waveform references, and all content item types supported by Basic Text SR.
///
/// Reference: PS3.3 Section A.35.2 - Enhanced SR
/// Reference: PS3.4 Annex B - Storage Service Class (Enhanced SR)

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Enhanced SR documents
///
/// EnhancedSRBuilder provides an API for creating structured reports that include
/// numeric measurements along with text content. This is ideal for reports that
/// need to include quantitative data such as tumor measurements, organ dimensions,
/// or other numerical findings.
///
/// Example:
/// ```swift
/// let document = try EnhancedSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle("CT Measurement Report")
///     .addSection("Findings") { section in
///         section.addText("Liver lesion identified.")
///         section.addNumeric(
///             conceptName: CodedConcept.diameter,
///             value: 25.5,
///             units: UCUMUnit.millimeter.asCodedConcept()
///         )
///     }
///     .addSection("Impression") { section in
///         section.addText("Small hepatic lesion, recommend follow-up.")
///     }
///     .build()
/// ```
///
/// ## Supported Value Types
/// Enhanced SR supports all Basic Text SR value types plus:
/// - NUM - Numeric measurements with units
/// - WAVEFORM - Waveform references (ECG, etc.)
///
/// Supported from Basic Text SR:
/// - TEXT - Free-form text content
/// - CODE - Coded concept values
/// - DATETIME, DATE, TIME - Temporal values
/// - UIDREF - UID reference values
/// - PNAME - Person name values
/// - COMPOSITE, IMAGE - Reference types
/// - CONTAINER - For hierarchical structure
///
/// Note: SCOORD (2D spatial coordinates), SCOORD3D (3D coordinates), and TCOORD
/// (temporal coordinates) are NOT supported in Enhanced SR. Use `ComprehensiveSRBuilder`
/// or `SRDocumentBuilder` with `.comprehensiveSR` for reports requiring coordinates.
public struct EnhancedSRBuilder: Sendable {
    
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
    
    /// Root-level content items (sections, text, measurements)
    public private(set) var contentItems: [AnyContentItem] = []
    
    // MARK: - Initialization
    
    /// Creates a new Enhanced SR document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> EnhancedSRBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> EnhancedSRBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> EnhancedSRBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> EnhancedSRBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> EnhancedSRBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> EnhancedSRBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> EnhancedSRBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> EnhancedSRBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> EnhancedSRBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> EnhancedSRBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> EnhancedSRBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> EnhancedSRBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> EnhancedSRBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> EnhancedSRBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> EnhancedSRBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> EnhancedSRBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> EnhancedSRBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title using a coded concept
    /// - Parameter title: The document title as a coded concept
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> EnhancedSRBuilder {
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
    public func withDocumentTitle(_ title: String) -> EnhancedSRBuilder {
        var copy = self
        copy.documentTitleString = title
        copy.documentTitle = nil
        return copy
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> EnhancedSRBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> EnhancedSRBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> EnhancedSRBuilder {
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
    public func addText(_ value: String, conceptName: CodedConcept? = nil) -> EnhancedSRBuilder {
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
    public func addLabeledText(label: String, value: String) -> EnhancedSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addText(value, conceptName: conceptName)
    }
    
    // MARK: - Content Addition - Numeric Measurements
    
    /// Adds a numeric measurement content item
    /// - Parameters:
    ///   - conceptName: The concept name for this measurement
    ///   - value: The numeric value
    ///   - units: The measurement units (coded concept)
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil
    ) -> EnhancedSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a numeric measurement with multiple values
    /// - Parameters:
    ///   - conceptName: The concept name for this measurement
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - qualifier: Optional qualifier for special values (e.g., "below detectable limit")
    /// - Returns: Updated builder
    public func addNumeric(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        qualifier: NumericValueQualifier? = nil
    ) -> EnhancedSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: values,
            units: units,
            floatingPointValues: nil,
            qualifier: qualifier,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a measurement with a label and value in millimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in millimeters
    /// - Returns: Updated builder
    public func addMeasurementMM(label: String, value: Double) -> EnhancedSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.millimeter.concept)
    }
    
    /// Adds a measurement with a label and value in centimeters
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The measurement value in centimeters
    /// - Returns: Updated builder
    public func addMeasurementCM(label: String, value: Double) -> EnhancedSRBuilder {
        let conceptName = CodedConcept.textLabel(label)
        return addNumeric(conceptName: conceptName, value: value, units: UCUMUnit.centimeter.concept)
    }
    
    // MARK: - Content Addition - Sections
    
    /// Adds a section (container) with nested content
    ///
    /// Sections provide hierarchical organization for Enhanced SR documents.
    /// Each section can contain text, codes, numeric measurements, and nested subsections.
    ///
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - builder: A closure that builds the section's content using an EnhancedSectionBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: CodedConcept,
        @EnhancedSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> EnhancedSRBuilder {
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
    ///   - builder: A closure that builds the section's content using an EnhancedSectionBuilder
    /// - Returns: Updated builder
    public func addSection(
        _ title: String,
        @EnhancedSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> EnhancedSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, builder: builder)
    }
    
    /// Adds a section with pre-built content items
    /// - Parameters:
    ///   - title: The section title as a coded concept
    ///   - items: The content items for the section
    /// - Returns: Updated builder
    public func addSection(_ title: CodedConcept, items: [AnyContentItem]) -> EnhancedSRBuilder {
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
    public func addSection(_ title: String, items: [AnyContentItem]) -> EnhancedSRBuilder {
        let concept = CodedConcept.sectionHeading(title)
        return addSection(concept, items: items)
    }
    
    // MARK: - Content Addition - Codes
    
    /// Adds a code content item
    /// - Parameters:
    ///   - conceptName: The concept name for this item
    ///   - value: The coded value
    /// - Returns: Updated builder
    public func addCode(conceptName: CodedConcept?, value: CodedConcept) -> EnhancedSRBuilder {
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
    public func addPersonName(conceptName: CodedConcept? = nil, name: String) -> EnhancedSRBuilder {
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
    public func addUIDRef(conceptName: CodedConcept? = nil, uid: String) -> EnhancedSRBuilder {
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
    public func addDate(conceptName: CodedConcept? = nil, date: String) -> EnhancedSRBuilder {
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
    public func addTime(conceptName: CodedConcept? = nil, time: String) -> EnhancedSRBuilder {
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
    public func addDateTime(conceptName: CodedConcept? = nil, datetime: String) -> EnhancedSRBuilder {
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
    ) -> EnhancedSRBuilder {
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
    
    /// Adds a composite reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced composite object
    ///   - sopInstanceUID: The SOP Instance UID of the referenced composite object
    /// - Returns: Updated builder
    public func addCompositeReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String
    ) -> EnhancedSRBuilder {
        var copy = self
        copy.contentItems.append(AnyContentItem(CompositeContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a waveform reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name for this item
    ///   - sopClassUID: The SOP Class UID of the referenced waveform
    ///   - sopInstanceUID: The SOP Instance UID of the referenced waveform
    ///   - channelNumbers: Optional channel numbers
    /// - Returns: Updated builder
    public func addWaveformReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        channelNumbers: [Int]? = nil
    ) -> EnhancedSRBuilder {
        var copy = self
        let sopRef = ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        let waveformRef = WaveformReference(
            sopReference: sopRef,
            channelNumbers: channelNumbers
        )
        copy.contentItems.append(AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: .contains
        )))
        return copy
    }
    
    /// Adds a pre-built content item
    /// - Parameter item: The content item to add
    /// - Returns: Updated builder
    public func addItem(_ item: AnyContentItem) -> EnhancedSRBuilder {
        var copy = self
        copy.contentItems.append(item)
        return copy
    }
    
    // MARK: - Common Report Sections
    
    /// Adds a "Findings" section with text content
    /// - Parameter text: The findings text
    /// - Returns: Updated builder
    public func addFindings(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.findings) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds an "Impression" section with text content
    /// - Parameter text: The impression text
    /// - Returns: Updated builder
    public func addImpression(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.impression) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Clinical History" section with text content
    /// - Parameter text: The clinical history text
    /// - Returns: Updated builder
    public func addClinicalHistory(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.clinicalHistory) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Conclusion" section with text content
    /// - Parameter text: The conclusion text
    /// - Returns: Updated builder
    public func addConclusion(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.conclusion) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Recommendation" section with text content
    /// - Parameter text: The recommendation text
    /// - Returns: Updated builder
    public func addRecommendation(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.recommendation) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Procedure Description" section with text content
    /// - Parameter text: The procedure description text
    /// - Returns: Updated builder
    public func addProcedureDescription(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.procedureDescription) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Comparison" section with text content
    /// - Parameter text: The comparison text
    /// - Returns: Updated builder
    public func addComparison(_ text: String) -> EnhancedSRBuilder {
        addSection(CodedConcept.comparison) {
            EnhancedSectionContent.text(text)
        }
    }
    
    /// Adds a "Measurements" section with nested measurements
    /// - Parameter builder: A closure that builds the measurements section content
    /// - Returns: Updated builder
    public func addMeasurements(
        @EnhancedSectionContentBuilder builder: () -> [AnyContentItem]
    ) -> EnhancedSRBuilder {
        addSection(CodedConcept.measurements, builder: builder)
    }
    
    // MARK: - Build
    
    /// Builds the Enhanced SR document
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
            sopClassUID: SRDocumentType.enhancedSR.sopClassUID,
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
    
    /// Validation errors for Enhanced SR documents
    public enum BuildError: Error, Sendable, Equatable {
        /// Content item uses value type not allowed in Enhanced SR
        case unsupportedValueType(valueType: ContentItemValueType)
        
        /// Description of the error
        public var localizedDescription: String {
            switch self {
            case .unsupportedValueType(let valueType):
                return "Value type '\(valueType)' is not supported in Enhanced SR documents. Use ComprehensiveSRBuilder or SRDocumentBuilder with .comprehensiveSR for spatial/temporal coordinates."
            }
        }
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Check that all content items use value types compatible with Enhanced SR
        try validateValueTypes(items: contentItems)
    }
    
    /// Validates that all content items use value types compatible with Enhanced SR
    private func validateValueTypes(items: [AnyContentItem]) throws {
        let allowedTypes = SRDocumentType.enhancedSR.allowedValueTypes
        
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

// MARK: - Enhanced Section Content Builder

/// Result builder for constructing Enhanced SR section content items
@resultBuilder
public struct EnhancedSectionContentBuilder {
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

// MARK: - Enhanced Section Content Helpers

/// Helper enum for building Enhanced SR section content
public enum EnhancedSectionContent {
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
    
    /// Creates a numeric content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: The content item
    public static func numeric(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            value: value,
            units: units,
            relationshipType: .contains
        ))
    }
    
    /// Creates a numeric content item with a label and units
    /// - Parameters:
    ///   - label: The measurement label
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: The content item
    public static func measurement(
        label: String,
        value: Double,
        units: CodedConcept
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: CodedConcept.textLabel(label),
            value: value,
            units: units,
            relationshipType: .contains
        ))
    }
    
    /// Creates a numeric content item with multiple values
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - values: The numeric values
    ///   - units: The measurement units
    ///   - qualifier: Optional qualifier for special values
    /// - Returns: The content item
    public static func numeric(
        conceptName: CodedConcept? = nil,
        values: [Double],
        units: CodedConcept? = nil,
        qualifier: NumericValueQualifier? = nil
    ) -> AnyContentItem {
        AnyContentItem(NumericContentItem(
            conceptName: conceptName,
            values: values,
            units: units,
            floatingPointValues: nil,
            qualifier: qualifier,
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
    
    /// Creates a time content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - time: The time value
    /// - Returns: The content item
    public static func time(conceptName: CodedConcept? = nil, time: String) -> AnyContentItem {
        AnyContentItem(TimeContentItem(
            conceptName: conceptName,
            timeValue: time,
            relationshipType: .contains
        ))
    }
    
    /// Creates a datetime content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - datetime: The datetime value
    /// - Returns: The content item
    public static func datetime(conceptName: CodedConcept? = nil, datetime: String) -> AnyContentItem {
        AnyContentItem(DateTimeContentItem(
            conceptName: conceptName,
            dateTimeValue: datetime,
            relationshipType: .contains
        ))
    }
    
    /// Creates an image reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - frameNumbers: Optional frame numbers
    /// - Returns: The content item
    public static func imageReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) -> AnyContentItem {
        AnyContentItem(ImageContentItem(
            conceptName: conceptName,
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            relationshipType: .contains
        ))
    }
    
    /// Creates a waveform reference content item
    /// - Parameters:
    ///   - conceptName: Optional concept name
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - channelNumbers: Optional channel numbers
    /// - Returns: The content item
    public static func waveformReference(
        conceptName: CodedConcept? = nil,
        sopClassUID: String,
        sopInstanceUID: String,
        channelNumbers: [Int]? = nil
    ) -> AnyContentItem {
        let sopRef = ReferencedSOP(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID)
        let waveformRef = WaveformReference(
            sopReference: sopRef,
            channelNumbers: channelNumbers
        )
        return AnyContentItem(WaveformContentItem(
            conceptName: conceptName,
            waveformReference: waveformRef,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection (nested container)
    /// - Parameters:
    ///   - title: The section title
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(
        _ title: CodedConcept,
        items: [AnyContentItem]
    ) -> AnyContentItem {
        AnyContentItem(ContainerContentItem(
            conceptName: title,
            continuityOfContent: .separate,
            contentItems: items,
            relationshipType: .contains
        ))
    }
    
    /// Creates a subsection with a string title
    /// - Parameters:
    ///   - title: The section title as a string
    ///   - items: The section content items
    /// - Returns: The content item
    public static func subsection(
        _ title: String,
        items: [AnyContentItem]
    ) -> AnyContentItem {
        subsection(CodedConcept.sectionHeading(title), items: items)
    }
}

// MARK: - CodedConcept Extensions for Measurements

extension CodedConcept {
    /// Standard concept for the measurements container (TID 1500 row 6)
    public static let measurements = CodedConcept(
        codeValue: "126010",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Imaging Measurements"
    )

    /// Standard concept for diameter measurement (CID 7470)
    public static let diameter = CodedConcept(
        codeValue: "81827009",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Diameter"
    )

    /// Standard concept for length measurement (CID 7470)
    public static let length = CodedConcept(
        codeValue: "410668003",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Length"
    )

    /// Standard concept for area measurement (CID 7471)
    public static let area = CodedConcept(
        codeValue: "42798000",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Area"
    )

    /// Standard concept for volume measurement (CID 7472)
    public static let volume = CodedConcept(
        codeValue: "118565006",
        codingSchemeDesignator: "SCT",
        codeMeaning: "Volume"
    )
}
