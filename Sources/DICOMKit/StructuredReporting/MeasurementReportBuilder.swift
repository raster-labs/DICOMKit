// NEMA-verified: 2026a, checked 2026-09-29 — content tree rows (relationship, value type, concept name, nesting) per PS3.16 2026a Tables TID 1500, TID 1204, TID 1600/1601/1602, TID 1501, TID 1502 and TID 300; TID 1204 row 2 and TID 1501 row 7 nested in the parent CODE's Content Sequence per PS3.3 Table C.17-6 (D31); CID 7021 titles (126000-126003) per Table CID 7021; concept meanings per Table D-1.
// NEMA-verified: 2026a, checked 2026-09-30 — P-MGC: TID 1501 rows 6-8 (row 8 Topographical modifier nested under the Finding Site), rows 10c/10d (SCOORD with its SELECTED FROM IMAGE child) and rows 11/11b; TID 300 rows 1/1b → TID 301 rows 2-7 and 13 → TID 320 rows 1, 3, 4 and 6 nested under the NUM; row, relationship, value type, concept name, VM and requirement compared by script against the PS3.16 2026a DocBook tables. TID 301 rows 8-12 and 14-19, TID 320 rows 2 and 5 (by-reference) and TID 1501 rows 3a, 5, 9-9d, 10f-10h are not written.
// NEMA-verified: 2026a, checked 2026-10-01 — D199: root Content Template Sequence (DCMR, 1500) per PS3.3 2026a Table C.18.8-1; TID 1500 rows 3 (→ TID 1001 row 1 → TID 1002 rows 1-3 → TID 1003 rows 1-2 / TID 1004 rows 1-5), 6b and 12b and TID 1501 row 9b (→ TID 4019 rows 1, 2, 2b, 3, 4), row 6 MC "IF Row 10 and Row 12 are absent"; 14 concept meanings compared with PS3.16 2026a Table D-1; Patient's Birth Date / Sex and Referring Physician's Name passed to SRDocument (D198)
/// TID 1500 Measurement Report Builder
///
/// Provides a specialized fluent API for creating DICOM TID 1500 Measurement Report
/// documents. These reports are used for quantitative imaging, AI/ML outputs, and
/// structured measurement data from imaging studies.
///
/// Reference: PS3.16 TID 1500 - Measurement Report
/// Reference: PS3.3 Section A.35.3 - Comprehensive SR (base IOD)

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM TID 1500 Measurement Report documents
///
/// MeasurementReportBuilder provides an API for creating structured reports that contain
/// imaging measurements, image libraries, and qualitative evaluations. This template is
/// widely used for quantitative imaging workflows and AI/ML detection outputs.
///
/// Example:
/// ```swift
/// let report = try MeasurementReportBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withDocumentTitle(MeasurementReportDocumentTitle.imagingMeasurementReport)
///     .addImageLibraryEntry(
///         sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
///         sopInstanceUID: "1.2.3.4.5.6.7.8.9"
///     )
///     .addMeasurementGroup(
///         trackingIdentifier: "Lesion 1",
///         trackingUID: "1.2.3.4.5.6.7.8.10"
///     ) {
///         MeasurementGroupContentHelper.longAxisMM(value: 25.5)
///         MeasurementGroupContentHelper.shortAxisMM(value: 18.2)
///     }
///     .build()
/// ```
///
/// ## Supported Content
/// - Image Library: References to source images used for measurements
/// - Measurement Groups: Organized groups of related measurements with tracking
/// - Qualitative Evaluations: Coded assessments and findings
/// - Observation Context: Observer and subject context information
///
/// ## Base IOD
/// TID 1500 uses the Comprehensive SR IOD, supporting all its value types.
public struct MeasurementReportBuilder: Sendable {
    
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
    
    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .partial
    
    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified
    
    /// Preliminary Flag
    public private(set) var preliminaryFlag: PreliminaryFlag?
    
    // MARK: - Procedure Information
    
    /// Procedure Reported codes
    public private(set) var proceduresReported: [CodedConcept] = []
    
    // MARK: - Language
    
    /// Language of content
    public private(set) var languageOfContent: CodedConcept?
    
    /// Country of language
    public private(set) var countryOfLanguage: CodedConcept?
    
    // MARK: - Content Structures
    
    /// Image library entries
    public private(set) var imageLibraryEntries: [ImageLibraryEntry] = []
    
    /// Measurement groups (TID 1501)
    public private(set) var measurementGroups: [MeasurementGroupData] = []
    
    /// Qualitative evaluations
    public private(set) var qualitativeEvaluations: [CodedConcept] = []
    
    /// Concept name of each entry in `qualitativeEvaluations`, by index.
    public private(set) var qualitativeEvaluationConceptNames: [CodedConcept] = []

    // MARK: - Observation Context and Algorithm Identification

    /// TID 1500 row 3 → TID 1001 row 1 → TID 1002: the observers, in order
    public private(set) var observers: [MeasurementReportObserver] = []

    /// TID 1500 row 6b → TID 4019, under the Imaging Measurements container
    public private(set) var imagingMeasurementsAlgorithm: CADAlgorithmIdentification?

    /// TID 1500 row 12b → TID 4019, under the Qualitative Evaluations container
    public private(set) var qualitativeEvaluationsAlgorithm: CADAlgorithmIdentification?
    
    // MARK: - Initialization
    
    /// Creates a new Measurement Report builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }
    
    // MARK: - Document Identification Setters
    
    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID
    /// - Returns: Updated builder
    public func withSOPInstanceUID(_ uid: String) -> MeasurementReportBuilder {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }
    
    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: Updated builder
    public func withStudyInstanceUID(_ uid: String) -> MeasurementReportBuilder {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }
    
    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID
    /// - Returns: Updated builder
    public func withSeriesInstanceUID(_ uid: String) -> MeasurementReportBuilder {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }
    
    /// Sets the Instance Number
    /// - Parameter number: The instance number
    /// - Returns: Updated builder
    public func withInstanceNumber(_ number: String) -> MeasurementReportBuilder {
        var copy = self
        copy.instanceNumber = number
        return copy
    }
    
    // MARK: - Patient Information Setters
    
    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: Updated builder
    public func withPatientID(_ id: String) -> MeasurementReportBuilder {
        var copy = self
        copy.patientID = id
        return copy
    }
    
    /// Sets the Patient Name
    /// - Parameter name: The patient name in DICOM PN format (e.g., "Doe^John")
    /// - Returns: Updated builder
    public func withPatientName(_ name: String) -> MeasurementReportBuilder {
        var copy = self
        copy.patientName = name
        return copy
    }
    
    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withPatientBirthDate(_ date: String) -> MeasurementReportBuilder {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }
    
    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, or O)
    /// - Returns: Updated builder
    public func withPatientSex(_ sex: String) -> MeasurementReportBuilder {
        var copy = self
        copy.patientSex = sex
        return copy
    }
    
    // MARK: - Study Information Setters
    
    /// Sets the Study Date
    /// - Parameter date: The study date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withStudyDate(_ date: String) -> MeasurementReportBuilder {
        var copy = self
        copy.studyDate = date
        return copy
    }
    
    /// Sets the Study Time
    /// - Parameter time: The study time in DICOM TM format
    /// - Returns: Updated builder
    public func withStudyTime(_ time: String) -> MeasurementReportBuilder {
        var copy = self
        copy.studyTime = time
        return copy
    }
    
    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: Updated builder
    public func withStudyDescription(_ description: String) -> MeasurementReportBuilder {
        var copy = self
        copy.studyDescription = description
        return copy
    }
    
    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: Updated builder
    public func withAccessionNumber(_ number: String) -> MeasurementReportBuilder {
        var copy = self
        copy.accessionNumber = number
        return copy
    }
    
    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name in DICOM PN format
    /// - Returns: Updated builder
    public func withReferringPhysicianName(_ name: String) -> MeasurementReportBuilder {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }
    
    // MARK: - Series Information Setters
    
    /// Sets the Series Number
    /// - Parameter number: The series number
    /// - Returns: Updated builder
    public func withSeriesNumber(_ number: String) -> MeasurementReportBuilder {
        var copy = self
        copy.seriesNumber = number
        return copy
    }
    
    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: Updated builder
    public func withSeriesDescription(_ description: String) -> MeasurementReportBuilder {
        var copy = self
        copy.seriesDescription = description
        return copy
    }
    
    // MARK: - Document Information Setters
    
    /// Sets the Content Date
    /// - Parameter date: The content date in DICOM DA format (YYYYMMDD)
    /// - Returns: Updated builder
    public func withContentDate(_ date: String) -> MeasurementReportBuilder {
        var copy = self
        copy.contentDate = date
        return copy
    }
    
    /// Sets the Content Time
    /// - Parameter time: The content time in DICOM TM format
    /// - Returns: Updated builder
    public func withContentTime(_ time: String) -> MeasurementReportBuilder {
        var copy = self
        copy.contentTime = time
        return copy
    }
    
    /// Sets the Document Title using a coded concept
    /// - Parameter title: The document title as a coded concept (from CID 7021)
    /// - Returns: Updated builder
    public func withDocumentTitle(_ title: CodedConcept) -> MeasurementReportBuilder {
        var copy = self
        copy.documentTitle = title
        return copy
    }
    
    /// Sets the Document Title to Imaging Measurement Report
    /// - Returns: Updated builder
    public func withImagingMeasurementReportTitle() -> MeasurementReportBuilder {
        withDocumentTitle(MeasurementReportDocumentTitle.imagingMeasurementReport)
    }
    
    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: Updated builder
    public func withCompletionFlag(_ flag: CompletionFlag) -> MeasurementReportBuilder {
        var copy = self
        copy.completionFlag = flag
        return copy
    }
    
    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: Updated builder
    public func withVerificationFlag(_ flag: VerificationFlag) -> MeasurementReportBuilder {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }
    
    /// Sets the Preliminary Flag
    /// - Parameter flag: The preliminary flag
    /// - Returns: Updated builder
    public func withPreliminaryFlag(_ flag: PreliminaryFlag) -> MeasurementReportBuilder {
        var copy = self
        copy.preliminaryFlag = flag
        return copy
    }
    
    // MARK: - Procedure Reported
    
    /// Adds a procedure reported code
    /// - Parameter procedure: The procedure code
    /// - Returns: Updated builder
    public func addProcedureReported(_ procedure: CodedConcept) -> MeasurementReportBuilder {
        var copy = self
        copy.proceduresReported.append(procedure)
        return copy
    }
    
    // MARK: - Language Settings
    
    /// Sets the language of content
    /// - Parameters:
    ///   - language: The language code
    ///   - country: Optional country code
    /// - Returns: Updated builder
    public func withLanguage(_ language: CodedConcept, country: CodedConcept? = nil) -> MeasurementReportBuilder {
        var copy = self
        copy.languageOfContent = language
        copy.countryOfLanguage = country
        return copy
    }
    
    // MARK: - Image Library
    
    /// Adds an image library entry
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID of the referenced image
    ///   - sopInstanceUID: The SOP Instance UID of the referenced image
    ///   - frameNumbers: Optional specific frame numbers
    ///   - modality: Optional modality code
    ///   - targetRegion: Optional target region code
    ///   - laterality: Optional laterality code
    /// - Returns: Updated builder
    public func addImageLibraryEntry(
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil,
        modality: CodedConcept? = nil,
        targetRegion: CodedConcept? = nil,
        laterality: CodedConcept? = nil
    ) -> MeasurementReportBuilder {
        var copy = self
        let entry = ImageLibraryEntry(
            sopClassUID: sopClassUID,
            sopInstanceUID: sopInstanceUID,
            frameNumbers: frameNumbers,
            modality: modality,
            targetRegion: targetRegion,
            laterality: laterality
        )
        copy.imageLibraryEntries.append(entry)
        return copy
    }
    
    /// Adds multiple image library entries
    /// - Parameter entries: The image library entries to add
    /// - Returns: Updated builder
    public func addImageLibraryEntries(_ entries: [ImageLibraryEntry]) -> MeasurementReportBuilder {
        var copy = self
        copy.imageLibraryEntries.append(contentsOf: entries)
        return copy
    }
    
    // MARK: - Measurement Groups
    
    /// Adds a measurement group with the builder pattern
    /// - Parameters:
    ///   - trackingIdentifier: The human-readable tracking identifier for this group
    ///   - trackingUID: The unique identifier for tracking across studies (generated if not provided)
    ///   - builder: A closure that configures the measurement group
    /// - Returns: Updated builder
    public func addMeasurementGroup(
        trackingIdentifier: String,
        trackingUID: String? = nil,
        finding: CodedConcept? = nil,
        findingSite: CodedConcept? = nil,
        @MeasurementGroupContentBuilder builder: () -> [MeasurementGroupContent]
    ) -> MeasurementReportBuilder {
        var copy = self
        let contents = builder()
        let group = MeasurementGroupData(
            trackingIdentifier: trackingIdentifier,
            trackingUID: trackingUID ?? UIDGenerator.generateUID().value,
            finding: finding,
            findingSite: findingSite,
            contents: contents
        )
        copy.measurementGroups.append(group)
        return copy
    }
    
    /// Adds a pre-built measurement group
    /// - Parameter group: The measurement group data
    /// - Returns: Updated builder
    public func addMeasurementGroup(_ group: MeasurementGroupData) -> MeasurementReportBuilder {
        var copy = self
        copy.measurementGroups.append(group)
        return copy
    }
    
    // MARK: - Qualitative Evaluations
    
    /// Adds a qualitative evaluation
    /// - Parameters:
    ///   - conceptName: The evaluation concept name
    ///   - value: The evaluation value (coded)
    /// - Returns: Updated builder
    public func addQualitativeEvaluation(
        conceptName: CodedConcept,
        value: CodedConcept
    ) -> MeasurementReportBuilder {
        var copy = self
        copy.qualitativeEvaluations.append(value)
        copy.qualitativeEvaluationConceptNames.append(conceptName)
        return copy
    }
    
    // MARK: - Observation Context (TID 1001) and Algorithm Identification (TID 4019)

    /// Adds an observer: TID 1500 row 3 (HAS OBS CONTEXT, INCLUDE TID 1001) → TID 1001 row 1
    /// → TID 1002 (rows 1-3 → TID 1003 Person or TID 1004 Device). Observers are written in
    /// the order they are added, after TID 1204 and before Procedure reported (row 4).
    /// - Parameter observer: A person or a device observer
    /// - Returns: Updated builder
    public func addObserver(_ observer: MeasurementReportObserver) -> MeasurementReportBuilder {
        var copy = self
        copy.observers.append(observer)
        return copy
    }

    /// Sets TID 1500 row 6b: HAS CONCEPT MOD, INCLUDE TID 4019 (Algorithm Identification)
    /// under the Imaging Measurements container. Row 6 is then written even with no
    /// Measurement Group when the report has no Qualitative Evaluations (row 6 is MC "IF Row
    /// 10 and Row 12 are absent").
    /// - Parameter algorithm: TID 4019 rows 1 (Algorithm Name), 2 (Algorithm Version), 2b,
    ///   3 and 4
    /// - Returns: Updated builder
    public func withAlgorithmIdentification(_ algorithm: CADAlgorithmIdentification) -> MeasurementReportBuilder {
        var copy = self
        copy.imagingMeasurementsAlgorithm = algorithm
        return copy
    }

    /// Sets TID 1500 row 12b: HAS CONCEPT MOD, INCLUDE TID 4019 under the Qualitative
    /// Evaluations container (written only when there are qualitative evaluations)
    /// - Parameter algorithm: The algorithm that produced the qualitative evaluations
    /// - Returns: Updated builder
    public func withQualitativeEvaluationsAlgorithmIdentification(_ algorithm: CADAlgorithmIdentification) -> MeasurementReportBuilder {
        var copy = self
        copy.qualitativeEvaluationsAlgorithm = algorithm
        return copy
    }

    // MARK: - Build
    
    /// Builds the TID 1500 Measurement Report document
    /// - Returns: The constructed SR document
    /// - Throws: `BuildError` if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }
        
        // Generate UIDs if not provided
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value
        
        // Build content tree according to TID 1500 structure
        var rootContentItems: [AnyContentItem] = []
        
        // TID 1500 row 2: HAS CONCEPT MOD, INCLUDE TID 1204.
        // TID 1204 row 1: HAS CONCEPT MOD CODE (121049, DCM, "Language of Content Item and
        // Descendants").
        if let language = languageOfContent {
            // TID 1204 row 2: ">" HAS CONCEPT MOD CODE (121046, DCM, "Country of Language"),
            // a child of the language CODE item, in its Content Sequence (PS3.3 Table C.17-6).
            // Until 2026-09-29 (D31) it was written as the next root-level item;
            // `MeasurementReport` reads both placements.
            var languageChildren: [AnyContentItem] = []
            if let country = countryOfLanguage {
                languageChildren.append(AnyContentItem(CodeContentItem(
                    conceptName: CodedConcept.countryOfLanguage,
                    conceptCode: country,
                    relationshipType: .hasConceptMod
                )))
            }
            rootContentItems.append(AnyContentItem(CodeContentItem(
                conceptName: CodedConcept.languageOfContentItemAndDescendants,
                conceptCode: language,
                relationshipType: .hasConceptMod,
                contentItems: languageChildren
            )))
        }

        // TID 1500 row 3: HAS OBS CONTEXT, INCLUDE TID 1001 → row 1 → TID 1002 per observer
        for observer in observers {
            rootContentItems.append(contentsOf: observer.observerContextItems())
        }

        // TID 1500 row 4: HAS CONCEPT MOD CODE (121058, DCM, "Procedure reported"), 1-n
        for procedure in proceduresReported {
            rootContentItems.append(AnyContentItem(CodeContentItem(
                conceptName: Self.procedureReportedConcept,
                conceptCode: procedure,
                relationshipType: .hasConceptMod
            )))
        }

        // TID 1500 row 5: CONTAINS, INCLUDE TID 1600 (Image Library)
        if !imageLibraryEntries.isEmpty {
            rootContentItems.append(AnyContentItem(buildImageLibrary()))
        }

        // TID 1500 row 6: CONTAINS CONTAINER (126010, DCM, "Imaging Measurements");
        // row 6b: ">>" HAS CONCEPT MOD, INCLUDE TID 4019; row 9: ">>" CONTAINS, INCLUDE
        // TID 1501, 1-n. With an algorithm and no Qualitative Evaluations the container is
        // written without groups, as row 6 is MC "IF Row 10 and Row 12 are absent".
        if !measurementGroups.isEmpty || (imagingMeasurementsAlgorithm != nil && qualitativeEvaluations.isEmpty) {
            let algorithmItems = imagingMeasurementsAlgorithm.map { Self.algorithmIdentificationItems($0) } ?? []
            let measurementGroupItems = buildMeasurementGroupItems()
            let imagingMeasurementsContainer = ContainerContentItem(
                conceptName: Self.imagingMeasurementsConcept,
                continuityOfContent: .separate,
                contentItems: algorithmItems + measurementGroupItems,
                relationshipType: .contains
            )
            rootContentItems.append(AnyContentItem(imagingMeasurementsContainer))
        }

        // TID 1500 row 12: CONTAINS CONTAINER (C0034375, UMLS, "Qualitative Evaluations");
        // row 13: ">>" CONTAINS CODE, 1-n
        if !qualitativeEvaluations.isEmpty {
            let evaluationItems = qualitativeEvaluations.enumerated().map { index, evaluation in
                AnyContentItem(CodeContentItem(
                    conceptName: index < qualitativeEvaluationConceptNames.count
                        ? qualitativeEvaluationConceptNames[index] : nil,
                    conceptCode: evaluation,
                    relationshipType: .contains
                ))
            }
            // Row 12b: ">>" HAS CONCEPT MOD, INCLUDE TID 4019
            let algorithmItems = qualitativeEvaluationsAlgorithm.map { Self.algorithmIdentificationItems($0) } ?? []
            let evaluationsContainer = ContainerContentItem(
                conceptName: Self.qualitativeEvaluationsConcept,
                continuityOfContent: .separate,
                contentItems: algorithmItems + evaluationItems,
                relationshipType: .contains
            )
            rootContentItems.append(AnyContentItem(evaluationsContainer))
        }
        
        // Determine document title (default to Imaging Measurement Report)
        let finalDocumentTitle = documentTitle ?? MeasurementReportDocumentTitle.imagingMeasurementReport
        
        // Create the root container (TID 1500 row 1). Content Template Sequence (0040,A504)
        // with Mapping Resource DCMR and Template Identifier 1500: Type 1C, required when the
        // content was built from a template (PS3.3 2026a Table C.18.8-1); written since
        // 2026-10-01 (D199)
        let rootContent = ContainerContentItem(
            conceptName: finalDocumentTitle,
            continuityOfContent: .separate,
            contentItems: rootContentItems,
            templateIdentifier: Self.templateIdentifier,
            mappingResource: "DCMR"
        )
        
        return SRDocument(
            sopClassUID: SRDocumentType.comprehensiveSR.sopClassUID,
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
    
    // MARK: - Build Helpers

    /// Template Identifier (0040,DB00) of the root: TID 1500
    public static let templateIdentifier = "1500"

    /// TID 4019 rows 1 (TEXT Algorithm Name, M), 2 (TEXT Algorithm Version, M), 2b (TEXT
    /// Algorithm Manufacturer), 3 (TEXT Algorithm Parameters, 1-n) and 4 (CODE Algorithm
    /// Family), with the HAS CONCEPT MOD relationship of TID 1500 rows 6b, 10b and 12b and
    /// TID 1501 row 9b. Concepts per PS3.16 2026a TID 4019 / Table D-1.
    static func algorithmIdentificationItems(_ algorithm: CADAlgorithmIdentification) -> [AnyContentItem] {
        func dcm(_ value: String, _ meaning: String) -> CodedConcept {
            CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
        }
        var items: [AnyContentItem] = [
            AnyContentItem(TextContentItem(conceptName: dcm("111001", "Algorithm Name"), textValue: algorithm.name, relationshipType: .hasConceptMod)),
            AnyContentItem(TextContentItem(conceptName: dcm("111003", "Algorithm Version"), textValue: algorithm.version, relationshipType: .hasConceptMod)),
        ]
        if let manufacturer = algorithm.manufacturer {
            items.append(AnyContentItem(TextContentItem(conceptName: dcm("122405", "Algorithm Manufacturer"), textValue: manufacturer, relationshipType: .hasConceptMod)))
        }
        for parameter in algorithm.parameters {
            items.append(AnyContentItem(TextContentItem(conceptName: dcm("111002", "Algorithm Parameters"), textValue: parameter, relationshipType: .hasConceptMod)))
        }
        if let family = algorithm.family {
            items.append(AnyContentItem(CodeContentItem(conceptName: dcm("111000", "Algorithm Family"), conceptCode: family, relationshipType: .hasConceptMod)))
        }
        return items
    }
    
    // MARK: Concept names (PS3.16 2026a Table D-1 meanings)

    /// (121058, DCM, "Procedure reported") — TID 1500 row 4
    static let procedureReportedConcept = CodedConcept(
        codeValue: "121058", codingSchemeDesignator: "DCM", codeMeaning: "Procedure reported")
    /// (111028, DCM, "Image Library") — TID 1600 row 1
    static let imageLibraryConcept = CodedConcept(
        codeValue: "111028", codingSchemeDesignator: "DCM", codeMeaning: "Image Library")
    /// (126200, DCM, "Image Library Group") — TID 1600 row 2
    static let imageLibraryGroupConcept = CodedConcept(
        codeValue: "126200", codingSchemeDesignator: "DCM", codeMeaning: "Image Library Group")
    /// (121139, DCM, "Modality") — TID 1602 row 1
    static let modalityConcept = CodedConcept(
        codeValue: "121139", codingSchemeDesignator: "DCM", codeMeaning: "Modality")
    /// (123014, DCM, "Target Region") — TID 1602 row 2
    static let targetRegionConcept = CodedConcept(
        codeValue: "123014", codingSchemeDesignator: "DCM", codeMeaning: "Target Region")
    /// (111027, DCM, "Image Laterality") — TID 1602 row 3
    static let imageLateralityConcept = CodedConcept(
        codeValue: "111027", codingSchemeDesignator: "DCM", codeMeaning: "Image Laterality")
    /// (126010, DCM, "Imaging Measurements") — TID 1500 row 6
    static let imagingMeasurementsConcept = CodedConcept(
        codeValue: "126010", codingSchemeDesignator: "DCM", codeMeaning: "Imaging Measurements")
    /// (C0034375, UMLS, "Qualitative Evaluations") — TID 1500 row 12
    static let qualitativeEvaluationsConcept = CodedConcept(
        codeValue: "C0034375", codingSchemeDesignator: "UMLS", codeMeaning: "Qualitative Evaluations")
    /// (125007, DCM, "Measurement Group") — TID 1501 row 1
    static let measurementGroupConcept = CodedConcept(
        codeValue: "125007", codingSchemeDesignator: "DCM", codeMeaning: "Measurement Group")
    /// (C67447, NCIt, "Activity Session") — TID 1501 row 1b
    static let activitySessionConcept = CodedConcept(
        codeValue: "C67447", codingSchemeDesignator: "NCIt", codeMeaning: "Activity Session")
    /// (112039, DCM, "Tracking Identifier") — TID 1501 row 2
    static let trackingIdentifierConcept = CodedConcept(
        codeValue: "112039", codingSchemeDesignator: "DCM", codeMeaning: "Tracking Identifier")
    /// (112040, DCM, "Tracking Unique Identifier") — TID 1501 row 3
    static let trackingUniqueIdentifierConcept = CodedConcept(
        codeValue: "112040", codingSchemeDesignator: "DCM", codeMeaning: "Tracking Unique Identifier")
    /// (121071, DCM, "Finding") — TID 1501 row 3b
    static let findingConcept = CodedConcept(
        codeValue: "121071", codingSchemeDesignator: "DCM", codeMeaning: "Finding")
    /// (C2348792, UMLS, "Time Point") — TID 1502 row 3 (TID 1501 row 4)
    static let timePointConcept = CodedConcept(
        codeValue: "C2348792", codingSchemeDesignator: "UMLS", codeMeaning: "Time Point")
    /// (363698007, SCT, "Finding Site") — TID 1501 row 6
    static let findingSiteConcept = CodedConcept(
        codeValue: "363698007", codingSchemeDesignator: "SCT", codeMeaning: "Finding Site")
    /// (272741003, SCT, "Laterality") — TID 1501 row 7
    static let lateralityConcept = CodedConcept(
        codeValue: "272741003", codingSchemeDesignator: "SCT", codeMeaning: "Laterality")
    /// DT (106233006, SCT, "Topographical modifier") — TID 1501 row 8, TID 301 row 7
    static let topographicalModifierConcept = CodedConcept(
        codeValue: "106233006", codingSchemeDesignator: "SCT", codeMeaning: "Topographical modifier")
    /// (370129005, SCT, "Measurement Method") — TID 301 row 3
    static let measurementMethodConcept = CodedConcept(
        codeValue: "370129005", codingSchemeDesignator: "SCT", codeMeaning: "Measurement Method")
    /// (121401, DCM, "Derivation") — TID 301 row 4
    static let derivationConcept = CodedConcept(
        codeValue: "121401", codingSchemeDesignator: "DCM", codeMeaning: "Derivation")

    /// A Finding Site CODE with its Laterality and Topographical modifier children: TID 1501
    /// rows 6-8 and TID 301 rows 5-7 have the same shape (HAS CONCEPT MOD CODE (363698007,
    /// SCT); ">" HAS CONCEPT MOD CODE (272741003, SCT), VM 1; ">" HAS CONCEPT MOD CODE DT
    /// (106233006, SCT), VM 1). The children go in the site's Content Sequence (PS3.3 Table
    /// C.17-6).
    static func findingSiteItem(
        _ site: CodedConcept,
        laterality: CodedConcept?,
        topographicalModifier: CodedConcept?
    ) -> AnyContentItem {
        var children: [AnyContentItem] = []
        if let laterality {
            children.append(AnyContentItem(CodeContentItem(
                conceptName: lateralityConcept, conceptCode: laterality, relationshipType: .hasConceptMod)))
        }
        if let topographicalModifier {
            children.append(AnyContentItem(CodeContentItem(
                conceptName: topographicalModifierConcept, conceptCode: topographicalModifier,
                relationshipType: .hasConceptMod)))
        }
        return AnyContentItem(CodeContentItem(
            conceptName: findingSiteConcept,
            conceptCode: site,
            relationshipType: .hasConceptMod,
            contentItems: children
        ))
    }

    /// Builds the Image Library (PS3.16 TID 1600):
    /// - row 1: CONTAINER (111028, DCM, "Image Library"), CONTAINS under the root;
    /// - row 2: ">" CONTAINS CONTAINER (126200, DCM, "Image Library Group"), 1-n;
    /// - row 3: ">>" HAS ACQ CONTEXT, INCLUDE TID 1602 (the descriptors shared by the group);
    /// - row 4: ">>" CONTAINS, INCLUDE TID 1601 (row 1: IMAGE), 1-n.
    ///
    /// Entries that share the same Modality / Target Region / Image Laterality are placed
    /// in one group and the descriptors are written once at group level (TID 1600 row 3),
    /// so TID 1601 row 2 (the same descriptors as HAS ACQ CONTEXT children of each IMAGE,
    /// U) is not used.
    private func buildImageLibrary() -> ContainerContentItem {
        struct Descriptors: Hashable {
            let modality: CodedConcept?
            let targetRegion: CodedConcept?
            let laterality: CodedConcept?
        }

        var order: [Descriptors] = []
        var members: [Descriptors: [ImageLibraryEntry]] = [:]
        for entry in imageLibraryEntries {
            let key = Descriptors(modality: entry.modality, targetRegion: entry.targetRegion, laterality: entry.laterality)
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(entry)
        }

        let groups: [AnyContentItem] = order.map { key in
            var groupItems: [AnyContentItem] = []

            // TID 1600 row 3 → TID 1602 rows 1-3: HAS ACQ CONTEXT CODE
            if let modality = key.modality {
                groupItems.append(AnyContentItem(CodeContentItem(
                    conceptName: Self.modalityConcept, conceptCode: modality, relationshipType: .hasAcqContext)))
            }
            if let targetRegion = key.targetRegion {
                groupItems.append(AnyContentItem(CodeContentItem(
                    conceptName: Self.targetRegionConcept, conceptCode: targetRegion, relationshipType: .hasAcqContext)))
            }
            if let laterality = key.laterality {
                groupItems.append(AnyContentItem(CodeContentItem(
                    conceptName: Self.imageLateralityConcept, conceptCode: laterality, relationshipType: .hasAcqContext)))
            }

            // TID 1600 row 4 → TID 1601 row 1: CONTAINS IMAGE (no concept name)
            for entry in members[key] ?? [] {
                groupItems.append(AnyContentItem(ImageContentItem(
                    conceptName: nil,
                    imageReference: ImageReference(
                        sopClassUID: entry.sopClassUID,
                        sopInstanceUID: entry.sopInstanceUID,
                        frameNumbers: entry.frameNumbers
                    ),
                    relationshipType: .contains
                )))
            }

            return AnyContentItem(ContainerContentItem(
                conceptName: Self.imageLibraryGroupConcept,
                continuityOfContent: .separate,
                contentItems: groupItems,
                relationshipType: .contains
            ))
        }

        return ContainerContentItem(
            conceptName: Self.imageLibraryConcept,
            continuityOfContent: .separate,
            contentItems: groups,
            relationshipType: .contains
        )
    }

    /// Builds the Measurement Group containers (PS3.16 TID 1501, included by TID 1500 row 9
    /// with CONTAINS). Rows are written in template order:
    /// - 1: CONTAINER (125007, DCM, "Measurement Group");
    /// - 1b: HAS OBS CONTEXT TEXT (C67447, NCIt, "Activity Session");
    /// - 2: HAS OBS CONTEXT TEXT (112039, DCM, "Tracking Identifier");
    /// - 3: HAS OBS CONTEXT UIDREF (112040, DCM, "Tracking Unique Identifier");
    /// - 3b: CONTAINS CODE (121071, DCM, "Finding");
    /// - 4: HAS OBS CONTEXT, INCLUDE TID 1502 (row 3: TEXT (C2348792, UMLS, "Time Point"));
    /// - 6: HAS CONCEPT MOD CODE (363698007, SCT, "Finding Site"), independent of row 3b;
    /// - 7: ">>" HAS CONCEPT MOD CODE (272741003, SCT, "Laterality") — a child of the
    ///   Finding Site CODE item, in its Content Sequence (PS3.3 Table C.17-6). Until
    ///   2026-09-29 (D31) it was written as the next HAS CONCEPT MOD item of the group;
    /// - 8: ">>" HAS CONCEPT MOD CODE DT (106233006, SCT, "Topographical modifier"), also a
    ///   child of the Finding Site (P-MGC, 2026-09-30);
    /// - 10, 10b-10e, 11, 11b, 12: the group's `contents` (see `MeasurementGroupContent`).
    private func buildMeasurementGroupItems() -> [AnyContentItem] {
        measurementGroups.map { group in
            var groupItems: [AnyContentItem] = []

            // Row 1b
            if let activitySession = group.activitySession {
                groupItems.append(AnyContentItem(TextContentItem(
                    conceptName: Self.activitySessionConcept,
                    textValue: activitySession,
                    relationshipType: .hasObsContext
                )))
            }

            // Row 2
            groupItems.append(AnyContentItem(TextContentItem(
                conceptName: Self.trackingIdentifierConcept,
                textValue: group.trackingIdentifier,
                relationshipType: .hasObsContext
            )))

            // Row 3
            groupItems.append(AnyContentItem(UIDRefContentItem(
                conceptName: Self.trackingUniqueIdentifierConcept,
                uidValue: group.trackingUID,
                relationshipType: .hasObsContext
            )))

            // Row 3b
            if let finding = group.finding {
                groupItems.append(AnyContentItem(CodeContentItem(
                    conceptName: Self.findingConcept,
                    conceptCode: finding,
                    relationshipType: .contains
                )))
            }

            // Row 4 → TID 1502 row 3
            if let timePoint = group.timePoint {
                groupItems.append(AnyContentItem(TextContentItem(
                    conceptName: Self.timePointConcept,
                    textValue: timePoint,
                    relationshipType: .hasObsContext
                )))
            }

            // Row 6, with rows 7 and 8 nested under it
            if let findingSite = group.findingSite {
                groupItems.append(Self.findingSiteItem(
                    findingSite,
                    laterality: group.laterality,
                    topographicalModifier: group.topographicalModifier
                ))
            }

            // Row 9b → TID 4019
            if let algorithm = group.algorithmIdentification {
                groupItems.append(contentsOf: Self.algorithmIdentificationItems(algorithm))
            }

            // Rows 10-12
            for content in group.contents {
                groupItems.append(content.toContentItem())
            }

            // Row 1
            return AnyContentItem(ContainerContentItem(
                conceptName: Self.measurementGroupConcept,
                continuityOfContent: .separate,
                contentItems: groupItems,
                relationshipType: .contains
            ))
        }
    }
    
    // MARK: - Validation
    
    /// Validation errors for Measurement Report documents
    public enum BuildError: Error, Sendable, Equatable {
        /// Measurement group is missing required tracking identifier
        case missingTrackingIdentifier
        
        /// Measurement group is missing required tracking UID
        case missingTrackingUID
        
        /// Description of the error
        public var localizedDescription: String {
            switch self {
            case .missingTrackingIdentifier:
                return "Measurement group is missing required tracking identifier"
            case .missingTrackingUID:
                return "Measurement group is missing required tracking UID"
            }
        }
    }
    
    /// Validates the builder configuration
    /// - Throws: `BuildError` if validation fails
    private func validate() throws {
        // Validate measurement groups have required tracking information
        for group in measurementGroups {
            if group.trackingIdentifier.isEmpty {
                throw BuildError.missingTrackingIdentifier
            }
            if group.trackingUID.isEmpty {
                throw BuildError.missingTrackingUID
            }
        }
    }
}

// MARK: - Supporting Types

/// Document title codes for measurement reports: the four rows of PS3.16 2026a
/// CID 7021 Measurement Report Document Title (DCM 126000-126003).
public enum MeasurementReportDocumentTitle {
    /// (126000, DCM, "Imaging Measurement Report")
    public static let imagingMeasurementReport = CodedConcept(
        codeValue: "126000",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Imaging Measurement Report"
    )

    /// (126001, DCM, "Oncology Measurement Report")
    public static let oncologyMeasurementReport = CodedConcept(
        codeValue: "126001",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Oncology Measurement Report"
    )

    /// (126002, DCM, "Dynamic Contrast MR Measurement Report")
    public static let dynamicContrastMRMeasurementReport = CodedConcept(
        codeValue: "126002",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Dynamic Contrast MR Measurement Report"
    )

    /// (126003, DCM, "PET Measurement Report")
    public static let petMeasurementReport = CodedConcept(
        codeValue: "126003",
        codingSchemeDesignator: "DCM",
        codeMeaning: "PET Measurement Report"
    )

    /// Misnamed: DCM 126002 is "Dynamic Contrast MR Measurement Report" in CID 7021; there
    /// is no "Lesion Measurement Report" title. The value is the correct CID 7021 concept.
    @available(*, deprecated, renamed: "dynamicContrastMRMeasurementReport")
    public static let lesionMeasurementReport = dynamicContrastMRMeasurementReport

    /// Misnamed: DCM 126003 is "PET Measurement Report" in CID 7021; there is no
    /// "CT Perfusion Analysis Report" title. The value is the correct CID 7021 concept.
    @available(*, deprecated, renamed: "petMeasurementReport")
    public static let ctPerfusionReport = petMeasurementReport
}

/// Entry in an image library (TID 320/1600)
public struct ImageLibraryEntry: Sendable, Equatable {
    /// SOP Class UID of the referenced image
    public let sopClassUID: String
    
    /// SOP Instance UID of the referenced image
    public let sopInstanceUID: String
    
    /// Optional specific frame numbers
    public let frameNumbers: [Int]?
    
    /// Optional modality code
    public let modality: CodedConcept?
    
    /// Optional target region code
    public let targetRegion: CodedConcept?
    
    /// Optional laterality code
    public let laterality: CodedConcept?
    
    /// Creates an image library entry
    public init(
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil,
        modality: CodedConcept? = nil,
        targetRegion: CodedConcept? = nil,
        laterality: CodedConcept? = nil
    ) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.frameNumbers = frameNumbers
        self.modality = modality
        self.targetRegion = targetRegion
        self.laterality = laterality
    }
}

/// Data for a measurement group (TID 1501)
public struct MeasurementGroupData: Sendable {
    /// Human-readable tracking identifier
    public let trackingIdentifier: String
    
    /// Unique tracking identifier (UID)
    public let trackingUID: String
    
    /// Optional activity session
    public var activitySession: String?
    
    /// Optional time point
    public var timePoint: String?
    
    /// Optional finding code
    public var finding: CodedConcept?
    
    /// Optional finding site
    public var findingSite: CodedConcept?
    
    /// Optional laterality: TID 1501 row 7, written under the Finding Site
    public var laterality: CodedConcept?

    /// Optional topographical modifier of the finding site: TID 1501 row 8, ">>" HAS CONCEPT
    /// MOD CODE DT (106233006, SCT, "Topographical modifier") ($TargetSiteMod), written under
    /// the Finding Site. Ignored when `findingSite` is nil, as it has no parent row then.
    public var topographicalModifier: CodedConcept?
    
    /// Content items (measurements, coordinates, etc.)
    public let contents: [MeasurementGroupContent]

    /// TID 1501 row 9b: HAS CONCEPT MOD, INCLUDE TID 4019 (Algorithm Identification) for
    /// this group (added 2026-10-01, D199)
    public var algorithmIdentification: CADAlgorithmIdentification?
    
    /// Creates a measurement group data structure
    public init(
        trackingIdentifier: String,
        trackingUID: String,
        activitySession: String? = nil,
        timePoint: String? = nil,
        finding: CodedConcept? = nil,
        findingSite: CodedConcept? = nil,
        laterality: CodedConcept? = nil,
        topographicalModifier: CodedConcept? = nil,
        contents: [MeasurementGroupContent] = []
    ) {
        self.trackingIdentifier = trackingIdentifier
        self.trackingUID = trackingUID
        self.activitySession = activitySession
        self.timePoint = timePoint
        self.finding = finding
        self.findingSite = findingSite
        self.laterality = laterality
        self.topographicalModifier = topographicalModifier
        self.contents = contents
    }
}

/// Content that can be added to a measurement group: the rows of PS3.16 TID 1501 from row 10
/// on, each written with CONTAINS as a direct child of the Measurement Group container.
///
/// `measurementWithContent`, `spatialCoordinatesOnImage` and
/// `qualitativeEvaluationWithModifiers` were added on 2026-09-30 (P-MGC) so that the rows
/// nested under a group item (TID 1501 rows 10d and 11b, TID 300 row 1b → TID 301 → TID 320)
/// can be written in that item's Content Sequence (PS3.3 Table C.17-6). They are new cases of
/// a public enum: a `switch` over this type without a `default` must handle them.
public enum MeasurementGroupContent: Sendable, Equatable {
    /// Numeric measurement: TID 1501 row 10 → TID 300 row 1, CONTAINS NUM, with no TID 301
    /// children. Use `measurementWithContent` to add them.
    case measurement(conceptName: CodedConcept?, value: Double, units: CodedConcept?)

    /// Multiple numeric values
    case measurements(conceptName: CodedConcept?, values: [Double], units: CodedConcept?)

    /// Qualitative evaluation: TID 1501 row 11, CONTAINS CODE ($QualType), with no row 11b
    /// children. Use `qualitativeEvaluationWithModifiers` to add them.
    case qualitativeEvaluation(conceptName: CodedConcept?, value: CodedConcept)

    /// Image reference: PS3.16 TID 1501 row 10b, ">" CONTAINS IMAGE ($ImagePurpose), a
    /// direct child of the Measurement Group. Until 2026-09-29 this was written with
    /// INFERRED FROM, a relationship TID 1501 does not define at group level. An image a
    /// measurement was inferred from (TID 300 row 1b → TID 301 row 13 → TID 320 row 1) goes
    /// under the NUM: use `measurementWithContent` with `MeasurementSource.image`.
    case imageReference(sopClassUID: String, sopInstanceUID: String, frameNumbers: [Int]?)

    /// 2D spatial coordinates: TID 1501 row 10c, ">" CONTAINS SCOORD, written **without**
    /// row 10d (">>" SELECTED FROM IMAGE, M), so the result does not conform to TID 1501 and
    /// a TID 1500 template validation reports the missing row. Use
    /// `spatialCoordinatesOnImage`, which writes row 10d. This case is kept for the SCOORD
    /// items of existing documents that have no source image.
    case spatialCoordinates(conceptName: CodedConcept?, graphicType: GraphicType, graphicData: [Float])

    /// 3D spatial coordinates: TID 1501 row 10e, ">" CONTAINS SCOORD3D ($ImagePurpose)
    case spatialCoordinates3D(conceptName: CodedConcept?, graphicType: GraphicType3D, graphicData: [Float], frameOfReferenceUID: String)

    /// Text value: TID 1501 row 12, CONTAINS TEXT ($QualType)
    case text(conceptName: CodedConcept?, value: String)

    /// A measurement with its children (P-MGC): TID 1501 row 10 → PS3.16 TID 300 row 1,
    /// CONTAINS NUM ($Measurement, UNITS = $Units, VM 1, M), and TID 300 row 1b (">" INCLUDE
    /// TID 301, M) written in the NUM's Content Sequence — see `MeasurementContent` for the
    /// TID 301 rows. `conceptName` and `units` are required because TID 300 row 1 is M.
    case measurementWithContent(conceptName: CodedConcept, value: Double, units: CodedConcept, content: MeasurementContent)

    /// 2D spatial coordinates with their source image (P-MGC): TID 1501 row 10c, ">" CONTAINS
    /// SCOORD ($ImagePurpose, VM 1-n, U), and row 10d, ">>" SELECTED FROM IMAGE (VM 1, M), in
    /// the SCOORD's Content Sequence.
    case spatialCoordinatesOnImage(conceptName: CodedConcept?, graphicType: GraphicType, graphicData: [Float], sourceImage: ImageReference)

    /// A qualitative evaluation with its modifiers (P-MGC): TID 1501 row 11, ">" CONTAINS CODE
    /// ($QualType = $QualValue), and row 11b, ">>" HAS CONCEPT MOD CODE ($QualModType =
    /// $QualModValue, VM 1-n, U), in the CODE's Content Sequence.
    case qualitativeEvaluationWithModifiers(conceptName: CodedConcept, value: CodedConcept, modifiers: [MeasurementConceptModifier])

    /// Converts this content to a content item
    func toContentItem() -> AnyContentItem {
        switch self {
        case .measurement(let conceptName, let value, let units):
            return AnyContentItem(NumericContentItem(
                conceptName: conceptName,
                value: value,
                units: units,
                relationshipType: .contains
            ))

        case .measurements(let conceptName, let values, let units):
            return AnyContentItem(NumericContentItem(
                conceptName: conceptName,
                values: values,
                units: units,
                floatingPointValues: nil,
                qualifier: nil,
                relationshipType: .contains
            ))

        case .qualitativeEvaluation(let conceptName, let value):
            return AnyContentItem(CodeContentItem(
                conceptName: conceptName,
                conceptCode: value,
                relationshipType: .contains
            ))

        case .imageReference(let sopClassUID, let sopInstanceUID, let frameNumbers):
            let imageRef = ImageReference(
                sopClassUID: sopClassUID,
                sopInstanceUID: sopInstanceUID,
                frameNumbers: frameNumbers
            )
            // TID 1501 row 10b: CONTAINS IMAGE
            return AnyContentItem(ImageContentItem(
                conceptName: nil,
                imageReference: imageRef,
                relationshipType: .contains
            ))

        case .spatialCoordinates(let conceptName, let graphicType, let graphicData):
            return AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: conceptName,
                graphicType: graphicType,
                graphicData: graphicData,
                relationshipType: .contains
            ))

        case .spatialCoordinates3D(let conceptName, let graphicType, let graphicData, let frameOfReferenceUID):
            return AnyContentItem(SpatialCoordinates3DContentItem(
                conceptName: conceptName,
                graphicType: graphicType,
                graphicData: graphicData,
                frameOfReferenceUID: frameOfReferenceUID,
                relationshipType: .contains
            ))

        case .text(let conceptName, let value):
            return AnyContentItem(TextContentItem(
                conceptName: conceptName,
                textValue: value,
                relationshipType: .contains
            ))

        case .measurementWithContent(let conceptName, let value, let units, let content):
            // TID 300 row 1: NUM; row 1b → TID 301: its Content Sequence
            return AnyContentItem(NumericContentItem(
                conceptName: conceptName,
                value: value,
                units: units,
                relationshipType: .contains,
                contentItems: content.contentItems()
            ))

        case .spatialCoordinatesOnImage(let conceptName, let graphicType, let graphicData, let sourceImage):
            // TID 1501 row 10c: SCOORD; row 10d: ">>" SELECTED FROM IMAGE, in its Content Sequence
            return AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: conceptName,
                graphicType: graphicType,
                graphicData: graphicData,
                relationshipType: .contains,
                contentItems: [AnyContentItem(ImageContentItem(
                    imageReference: sourceImage,
                    relationshipType: .selectedFrom
                ))]
            ))

        case .qualitativeEvaluationWithModifiers(let conceptName, let value, let modifiers):
            // TID 1501 row 11: CODE; row 11b: ">>" HAS CONCEPT MOD CODE, in its Content Sequence
            return AnyContentItem(CodeContentItem(
                conceptName: conceptName,
                conceptCode: value,
                relationshipType: .contains,
                contentItems: modifiers.map { $0.contentItem() }
            ))
        }
    }
}

// MARK: - TID 300 / 301 / 320 content of a measurement

/// A coded concept modifier: a HAS CONCEPT MOD CODE item whose concept name and value are
/// both codes. It is PS3.16 TID 301 row 2 ($ModType = $ModValue, VM 1-n) under a measurement,
/// and TID 1501 row 11b ($QualModType = $QualModValue, VM 1-n) under a qualitative evaluation.
public struct MeasurementConceptModifier: Sendable, Equatable, Hashable {
    /// The modifier's concept name ($ModType or $QualModType)
    public let conceptName: CodedConcept

    /// The modifier's value ($ModValue or $QualModValue)
    public let value: CodedConcept

    /// Creates a concept modifier
    public init(conceptName: CodedConcept, value: CodedConcept) {
        self.conceptName = conceptName
        self.value = value
    }

    func contentItem() -> AnyContentItem {
        AnyContentItem(CodeContentItem(conceptName: conceptName, conceptCode: value, relationshipType: .hasConceptMod))
    }
}

/// The anatomic location of a measurement: PS3.16 TID 301 row 5, HAS CONCEPT MOD CODE
/// (363698007, SCT, "Finding Site") ($TargetSite, VM 1-n), with row 6 (">" HAS CONCEPT MOD
/// CODE (272741003, SCT, "Laterality"), $TargetSiteLaterality, defaulting to DCID 244) and
/// row 7 (">" HAS CONCEPT MOD CODE DT (106233006, SCT, "Topographical modifier"),
/// $TargetSiteMod) in its Content Sequence.
public struct MeasurementFindingSite: Sendable, Equatable, Hashable {
    /// The finding site ($TargetSite)
    public let site: CodedConcept

    /// Laterality of the site (row 6)
    public let laterality: CodedConcept?

    /// Topographical modifier of the site (row 7)
    public let topographicalModifier: CodedConcept?

    /// Creates a finding site
    public init(site: CodedConcept, laterality: CodedConcept? = nil, topographicalModifier: CodedConcept? = nil) {
        self.site = site
        self.laterality = laterality
        self.topographicalModifier = topographicalModifier
    }
}

/// An image or spatial coordinates a measurement was inferred from: one instance of PS3.16
/// TID 320 "Image or Spatial Coordinates", included by TID 301 row 13 (VM 1-n,
/// $Purpose = $ImagePurpose). TID 320 rows 1, 3 and 6 are mutually exclusive, so each instance
/// is one of them. Rows 2 and 5 (R-INFERRED FROM, R-SELECTED FROM: by-reference relationships)
/// are not written.
public enum MeasurementSource: Sendable, Equatable, Hashable {
    /// TID 320 row 1: INFERRED FROM IMAGE ($Purpose)
    case image(purpose: CodedConcept?, image: ImageReference)

    /// TID 320 row 3: INFERRED FROM SCOORD ($Purpose), with row 4: ">" SELECTED FROM IMAGE
    /// in its Content Sequence. Row 4 is MC XOR row 5; row 5 is not written, so the image is
    /// required.
    case spatialCoordinates(purpose: CodedConcept?, graphicType: GraphicType, graphicData: [Float], sourceImage: ImageReference)

    /// TID 320 row 6: INFERRED FROM SCOORD3D ($Purpose)
    case spatialCoordinates3D(purpose: CodedConcept?, graphicType: GraphicType3D, graphicData: [Float], frameOfReferenceUID: String)

    func contentItem() -> AnyContentItem {
        switch self {
        case .image(let purpose, let image):
            return AnyContentItem(ImageContentItem(
                conceptName: purpose, imageReference: image, relationshipType: .inferredFrom))
        case .spatialCoordinates(let purpose, let graphicType, let graphicData, let sourceImage):
            return AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: purpose,
                graphicType: graphicType,
                graphicData: graphicData,
                relationshipType: .inferredFrom,
                contentItems: [AnyContentItem(ImageContentItem(
                    imageReference: sourceImage, relationshipType: .selectedFrom))]
            ))
        case .spatialCoordinates3D(let purpose, let graphicType, let graphicData, let frameOfReferenceUID):
            return AnyContentItem(SpatialCoordinates3DContentItem(
                conceptName: purpose,
                graphicType: graphicType,
                graphicData: graphicData,
                frameOfReferenceUID: frameOfReferenceUID,
                relationshipType: .inferredFrom
            ))
        }
    }
}

/// The children of a measurement NUM: the rows of PS3.16 TID 301 "Measurement Content"
/// (included by TID 300 row 1b) that the builder writes, in table order, in the NUM's Content
/// Sequence (PS3.3 Table C.17-6). TID 301 rows 8-12 and 14-19 are not written.
public struct MeasurementContent: Sendable, Equatable, Hashable {
    /// Row 2: HAS CONCEPT MOD CODE ($ModType = $ModValue), VM 1-n
    public var modifiers: [MeasurementConceptModifier]

    /// Row 3: HAS CONCEPT MOD CODE (370129005, SCT, "Measurement Method") ($Method), VM 1
    public var method: CodedConcept?

    /// Row 4: HAS CONCEPT MOD CODE (121401, DCM, "Derivation") ($Derivation), VM 1
    public var derivation: CodedConcept?

    /// Rows 5-7: HAS CONCEPT MOD CODE (363698007, SCT, "Finding Site"), VM 1-n, each with its
    /// Laterality and Topographical modifier
    public var findingSites: [MeasurementFindingSite]

    /// Row 13: INCLUDE TID 320, VM 1-n — the images and spatial coordinates the measurement
    /// was inferred from
    public var sources: [MeasurementSource]

    /// Creates measurement content
    public init(
        modifiers: [MeasurementConceptModifier] = [],
        method: CodedConcept? = nil,
        derivation: CodedConcept? = nil,
        findingSites: [MeasurementFindingSite] = [],
        sources: [MeasurementSource] = []
    ) {
        self.modifiers = modifiers
        self.method = method
        self.derivation = derivation
        self.findingSites = findingSites
        self.sources = sources
    }

    /// Whether no TID 301 row is set
    public var isEmpty: Bool {
        modifiers.isEmpty && method == nil && derivation == nil && findingSites.isEmpty && sources.isEmpty
    }

    /// The TID 301 rows as content items, in table order
    func contentItems() -> [AnyContentItem] {
        var items = modifiers.map { $0.contentItem() }                                  // row 2
        if let method {                                                                 // row 3
            items.append(AnyContentItem(CodeContentItem(
                conceptName: MeasurementReportBuilder.measurementMethodConcept,
                conceptCode: method, relationshipType: .hasConceptMod)))
        }
        if let derivation {                                                             // row 4
            items.append(AnyContentItem(CodeContentItem(
                conceptName: MeasurementReportBuilder.derivationConcept,
                conceptCode: derivation, relationshipType: .hasConceptMod)))
        }
        items += findingSites.map {                                                     // rows 5-7
            MeasurementReportBuilder.findingSiteItem(
                $0.site, laterality: $0.laterality, topographicalModifier: $0.topographicalModifier)
        }
        items += sources.map { $0.contentItem() }                                       // row 13
        return items
    }
}

// MARK: - Measurement Group Content Builder

/// Result builder for constructing measurement group content
@resultBuilder
public struct MeasurementGroupContentBuilder {
    /// Builds an empty block
    public static func buildBlock() -> [MeasurementGroupContent] {
        []
    }
    
    /// Builds a block from arrays of content
    public static func buildBlock(_ components: [MeasurementGroupContent]...) -> [MeasurementGroupContent] {
        components.flatMap { $0 }
    }
    
    /// Builds a block from arrays of content
    public static func buildArray(_ components: [[MeasurementGroupContent]]) -> [MeasurementGroupContent] {
        components.flatMap { $0 }
    }
    
    public static func buildOptional(_ component: [MeasurementGroupContent]?) -> [MeasurementGroupContent] {
        component ?? []
    }
    
    public static func buildEither(first component: [MeasurementGroupContent]) -> [MeasurementGroupContent] {
        component
    }
    
    public static func buildEither(second component: [MeasurementGroupContent]) -> [MeasurementGroupContent] {
        component
    }
    
    /// Builds from a single content item
    public static func buildExpression(_ expression: MeasurementGroupContent) -> [MeasurementGroupContent] {
        [expression]
    }
}

// MARK: - Measurement Group Content Helpers

/// Helper functions for creating measurement group content
public enum MeasurementGroupContentHelper {
    /// Creates a numeric measurement
    /// - Parameters:
    ///   - conceptName: The concept name for this measurement
    ///   - value: The numeric value
    ///   - units: The measurement units
    /// - Returns: Measurement group content
    public static func measurement(
        conceptName: CodedConcept? = nil,
        value: Double,
        units: CodedConcept? = nil
    ) -> MeasurementGroupContent {
        .measurement(conceptName: conceptName, value: value, units: units)
    }
    
    /// Creates a length measurement in millimeters
    /// - Parameters:
    ///   - value: The measurement value in millimeters
    /// - Returns: Measurement group content
    public static func lengthMM(value: Double) -> MeasurementGroupContent {
        .measurement(
            conceptName: CodedConcept(
                codeValue: "410668003",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Length"
            ),
            value: value,
            units: UCUMUnit.millimeter.concept
        )
    }
    
    /// Creates a long axis measurement in millimeters
    /// - Parameter value: The measurement value in millimeters
    /// - Returns: Measurement group content
    public static func longAxisMM(value: Double) -> MeasurementGroupContent {
        .measurement(
            conceptName: CodedConcept(
                codeValue: "103339001",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Long Axis"
            ),
            value: value,
            units: UCUMUnit.millimeter.concept
        )
    }
    
    /// Creates a short axis measurement in millimeters
    /// - Parameter value: The measurement value in millimeters
    /// - Returns: Measurement group content
    public static func shortAxisMM(value: Double) -> MeasurementGroupContent {
        .measurement(
            conceptName: CodedConcept(
                codeValue: "103340004",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Short Axis"
            ),
            value: value,
            units: UCUMUnit.millimeter.concept
        )
    }
    
    /// Creates an area measurement in square millimeters
    /// - Parameter value: The measurement value in mm²
    /// - Returns: Measurement group content
    public static func areaMM2(value: Double) -> MeasurementGroupContent {
        .measurement(
            conceptName: CodedConcept(
                codeValue: "42798000",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Area"
            ),
            value: value,
            units: UCUMUnit.squareMillimeter.concept
        )
    }
    
    /// Creates a volume measurement in cubic millimeters
    /// - Parameter value: The measurement value in mm³
    /// - Returns: Measurement group content
    public static func volumeMM3(value: Double) -> MeasurementGroupContent {
        .measurement(
            conceptName: CodedConcept(
                codeValue: "118565006",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Volume"
            ),
            value: value,
            units: UCUMUnit.cubicMillimeter.concept
        )
    }
    
    /// Creates an image reference
    /// - Parameters:
    ///   - sopClassUID: The SOP Class UID
    ///   - sopInstanceUID: The SOP Instance UID
    ///   - frameNumbers: Optional frame numbers
    /// - Returns: Measurement group content
    public static func imageReference(
        sopClassUID: String,
        sopInstanceUID: String,
        frameNumbers: [Int]? = nil
    ) -> MeasurementGroupContent {
        .imageReference(sopClassUID: sopClassUID, sopInstanceUID: sopInstanceUID, frameNumbers: frameNumbers)
    }
    
    /// Creates 2D spatial coordinates without their source image. TID 1501 row 10d (SELECTED
    /// FROM IMAGE, M) is then missing; prefer `coordinates(graphicType:graphicData:sourceImage:)`.
    /// - Parameters:
    ///   - graphicType: The type of graphic
    ///   - graphicData: The coordinate data
    /// - Returns: Measurement group content
    public static func coordinates(
        graphicType: GraphicType,
        graphicData: [Float]
    ) -> MeasurementGroupContent {
        .spatialCoordinates(conceptName: nil, graphicType: graphicType, graphicData: graphicData)
    }

    /// Creates 2D spatial coordinates with the image they were selected from: TID 1501 row 10c
    /// (CONTAINS SCOORD) with row 10d (">>" SELECTED FROM IMAGE) as its child.
    /// - Parameters:
    ///   - graphicType: The type of graphic
    ///   - graphicData: The coordinate data
    ///   - sourceImage: The image the coordinates are selected from
    /// - Returns: Measurement group content
    public static func coordinates(
        graphicType: GraphicType,
        graphicData: [Float],
        sourceImage: ImageReference
    ) -> MeasurementGroupContent {
        .spatialCoordinatesOnImage(conceptName: nil, graphicType: graphicType, graphicData: graphicData,
                                   sourceImage: sourceImage)
    }
}


// MARK: - Observer Context (TID 1002)

/// One observer of a Measurement Report: TID 1500 row 3 → TID 1001 row 1 → TID 1002
/// (PS3.16 2026a), every item HAS OBS CONTEXT at the root
public enum MeasurementReportObserver: Sendable, Equatable {
    /// TID 1002 row 2 → TID 1003: row 1 PNAME (121008, DCM, "Person Observer Name"), M;
    /// row 2 TEXT (121009, DCM, "Person Observer's Organization Name"), U. TID 1002 row 1
    /// (Observer Type) is left out, as it defaults to (121006, DCM, "Person").
    case person(name: String, organizationName: String? = nil)

    /// TID 1002 row 1 CODE (121005, DCM, "Observer Type") = (121007, DCM, "Device"), then
    /// row 3 → TID 1004: row 1 UIDREF (121012, DCM, "Device Observer UID"), M; rows 2-5
    /// TEXT (121013 Name, 121014 Manufacturer, 121015 Model Name, 121016 Serial Number), U
    case device(uid: String, name: String? = nil, manufacturer: String? = nil, modelName: String? = nil, serialNumber: String? = nil)

    /// The TID 1002 content items, relationship HAS OBS CONTEXT
    func observerContextItems() -> [AnyContentItem] {
        func dcm(_ value: String, _ meaning: String) -> CodedConcept {
            CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
        }
        func text(_ value: String, _ meaning: String, _ text: String) -> AnyContentItem {
            AnyContentItem(TextContentItem(conceptName: dcm(value, meaning), textValue: text, relationshipType: .hasObsContext))
        }
        switch self {
        case let .person(name, organizationName):
            var items = [AnyContentItem(PersonNameContentItem(
                conceptName: dcm("121008", "Person Observer Name"), personName: name, relationshipType: .hasObsContext))]
            if let organizationName {
                items.append(text("121009", "Person Observer's Organization Name", organizationName))
            }
            return items
        case let .device(uid, name, manufacturer, modelName, serialNumber):
            var items = [
                AnyContentItem(CodeContentItem(
                    conceptName: dcm("121005", "Observer Type"), conceptCode: dcm("121007", "Device"),
                    relationshipType: .hasObsContext)),
                AnyContentItem(UIDRefContentItem(
                    conceptName: dcm("121012", "Device Observer UID"), uidValue: uid, relationshipType: .hasObsContext)),
            ]
            if let name { items.append(text("121013", "Device Observer Name", name)) }
            if let manufacturer { items.append(text("121014", "Device Observer Manufacturer", manufacturer)) }
            if let modelName { items.append(text("121015", "Device Observer Model Name", modelName)) }
            if let serialNumber { items.append(text("121016", "Device Observer Serial Number", serialNumber)) }
            return items
        }
    }
}
