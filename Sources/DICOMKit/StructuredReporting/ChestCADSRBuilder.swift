// NEMA-verified: 2026a, checked 2026-09-29 — content tree built row by row from PS3.16 2026a TID 4100, 1204, 4020, 4101, 4104, 4105, 4107, 4015-4019; values from CID 6101, 6102/6104, 6034, 6042, 6047, 6137, 244, 4010, 4011; codes checked in Table D-1; value types per PS3.3 Table A.35.6-2 (no DATETIME). Children of non-CONTAINER nodes are nested in their Content Sequence per PS3.3 Table C.17-6 (D31, see CADSRNode). .lesion/.consolidation have no CID 6101/6102 code and are deprecated (99DICOMKIT).
/// Chest CAD SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Chest Computer-Aided Detection (CAD)
/// Structured Report documents. These documents encode the results of CAD analysis algorithms
/// that detect and characterize potential findings in chest radiographic and CT images,
/// particularly for lung nodule detection.
///
/// Reference: PS3.3 Section A.35.6 - Chest CAD SR IOD (Table A.35.6-2 relationship constraints)
/// Reference: PS3.16 TID 4100 - Chest CAD Document Root
/// Reference: PS3.16 TID 4101 - Chest CAD Findings Summary
/// Reference: PS3.16 TID 4104 - Chest CAD Single Image Finding
/// Reference: PS3.16 TID 4105 - Chest CAD Descriptors
/// Reference: PS3.16 TID 4107 - Chest CAD Geometry
/// Reference: PS3.16 TID 4015-4019 - CAD Detections/Analyses Performed, Algorithm Identification
/// Reference: PS3.16 TID 4020 - CAD Image Library Entry

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Chest CAD SR documents
///
/// The content tree follows PS3.16 TID 4100 (Chest CAD Document Root):
///
/// ```
/// CONTAINER (112000, DCM, "Chest CAD Report")                              TID 4100 row 1
///  ├ HAS CONCEPT MOD CODE (121049, DCM, "Language of Content Item and Descendants")  TID 1204
///  ├ CONTAINS CONTAINER (111028, DCM, "Image Library")                     row 3
///  │   └ CONTAINS IMAGE [+ HAS ACQ CONTEXT laterality, view, ...]           TID 4020
///  ├ CONTAINS CODE (111017, DCM, "CAD Processing and Findings Summary")    TID 4101 row 1, CID 6047
///  │   └ INFERRED FROM CODE (111059, DCM, "Single Image Finding")           TID 4104, CID 6101
///  │       ├ HAS CONCEPT MOD CODE (112024, DCM, "Single Image Finding Modifier")  CID 6102
///  │       ├ HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent")         CID 6034
///  │       ├ HAS OBS CONTEXT TEXT (111001, DCM, "Algorithm Name") ...       TID 4019
///  │       ├ HAS PROPERTIES NUM (111012, DCM, "Certainty of Finding")       %
///  │       ├ HAS PROPERTIES SCOORD (111010, DCM, "Center") ─ SELECTED FROM IMAGE  TID 4107
///  │       └ HAS PROPERTIES CODE descriptors                                TID 4105
///  ├ CONTAINS CODE (111064, DCM, "Summary of Detections")                  CID 6042
///  │   └ INFERRED FROM CONTAINER (111063, DCM, "Successful Detections")     TID 4015/4017
///  └ CONTAINS CODE (111065, DCM, "Summary of Analyses")                    CID 6042
///      └ INFERRED FROM CONTAINER (111062, DCM, "Successful Analyses")       TID 4016/4018
/// ```
///
/// Example:
/// ```swift
/// let document = try ChestCADSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^John")
///     .withCADProcessingSummary(
///         algorithmName: "ChestCAD v3.2",
///         algorithmVersion: "3.2.0",
///         manufacturer: "Example Medical Systems"
///     )
///     .addFinding(
///         type: .nodule,
///         probability: 0.92,
///         location: .point2D(x: 256.5, y: 384.7, imageReference: imageRef)
///     )
///     .build()
/// ```
///
/// ## Nesting
/// See ``MammographyCADSRBuilder``: children of CODE, IMAGE and SCOORD nodes (e.g. TID 4104
/// rows 2-18 under the Single Image Finding CODE, TID 4107 row 2 under the Center SCOORD)
/// are nested in that item's Content Sequence (PS3.3 Table C.17-6), with the template's
/// relationship type; by-reference rows are written by value.
///
/// ## Supported Content
/// Chest CAD SR documents support the value types of PS3.3 Table A.35.6-2:
/// TEXT, CODE, NUM, DATE, TIME, UIDREF, PNAME, COMPOSITE, IMAGE, WAVEFORM, SCOORD, TCOORD,
/// CONTAINER (DATETIME is not permitted).
public struct ChestCADSRBuilder: Sendable {

    // MARK: - Error Types

    /// Errors that can occur during building
    public enum BuildError: Error, Sendable, Equatable {
        /// Validation error
        case validationError(String)
    }

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

    /// Completion Flag
    public private(set) var completionFlag: CompletionFlag = .complete

    /// Verification Flag
    public private(set) var verificationFlag: VerificationFlag = .unverified

    // MARK: - CAD Processing Information

    /// CAD algorithm name (TID 4019 row 1)
    public private(set) var algorithmName: String?

    /// CAD algorithm version (TID 4019 row 2)
    public private(set) var algorithmVersion: String?

    /// Manufacturer of the CAD system (TID 4019 row 2b)
    public private(set) var manufacturer: String?

    /// Processing date/time. Never written: TID 4019 has no date/time row and PS3.3
    /// Table A.35.6-2 permits no DATETIME content item in a Chest CAD SR.
    @available(*, deprecated, message: "not written: TID 4019 (Algorithm Identification) has no date/time row and PS3.3 Table A.35.6-2 permits no DATETIME item in a Chest CAD SR")
    public var processingDateTime: String? { storedProcessingDateTime }
    private var storedProcessingDateTime: String?

    /// Language of the report (TID 4100 row 2 / TID 1204, CID 5000). Defaults to ("en", RFC5646, "English").
    public private(set) var language: CodedConcept = CADSRDefaults.english

    /// Country of language (TID 1204 row 2, CID 5001)
    public private(set) var countryOfLanguage: CodedConcept?

    /// Explicit Image Library entries (TID 4100 rows 3-4 / TID 4020: laterality CID 244,
    /// view CID 4010, view modifier CID 4011)
    public private(set) var imageLibraryEntries: [CADImageLibraryEntry] = []

    /// Explicit detections performed (TID 4017; codes from CID 6101 / CID 6102). When empty,
    /// one per distinct finding is derived from ``findings``.
    public private(set) var detectionsPerformed: [CADAlgorithmRun] = []

    /// Analyses performed (TID 4018; codes from CID 6137)
    public private(set) var analysesPerformed: [CADAlgorithmRun] = []

    /// Explicit (111064, DCM, "Summary of Detections") value; derived when nil
    public private(set) var summaryOfDetections: CADProcessingStatus?

    /// Explicit (111065, DCM, "Summary of Analyses") value; derived when nil
    public private(set) var summaryOfAnalyses: CADProcessingStatus?

    /// Explicit (111017, DCM, "CAD Processing and Findings Summary") value; derived when nil
    public private(set) var processingAndFindingsSummary: CADProcessingAndFindingsSummary?

    // MARK: - CAD Findings

    /// Detected CAD findings
    public private(set) var findings: [ChestCADFinding] = []

    // MARK: - Initialization

    /// Creates a new Chest CAD SR document builder
    /// - Parameter validateOnBuild: Whether to validate the document during build (default: true)
    public init(validateOnBuild: Bool = true) {
        self.validateOnBuild = validateOnBuild
    }

    // MARK: - Document Identification Setters

    /// Sets the SOP Instance UID
    /// - Parameter uid: The SOP Instance UID (or nil to auto-generate)
    /// - Returns: A new builder with the updated value
    public func withSOPInstanceUID(_ uid: String?) -> Self {
        var copy = self
        copy.sopInstanceUID = uid
        return copy
    }

    /// Sets the Study Instance UID
    /// - Parameter uid: The Study Instance UID
    /// - Returns: A new builder with the updated value
    public func withStudyInstanceUID(_ uid: String) -> Self {
        var copy = self
        copy.studyInstanceUID = uid
        return copy
    }

    /// Sets the Series Instance UID
    /// - Parameter uid: The Series Instance UID (or nil to auto-generate)
    /// - Returns: A new builder with the updated value
    public func withSeriesInstanceUID(_ uid: String?) -> Self {
        var copy = self
        copy.seriesInstanceUID = uid
        return copy
    }

    /// Sets the Instance Number
    /// - Parameter number: The instance number as string
    /// - Returns: A new builder with the updated value
    public func withInstanceNumber(_ number: String) -> Self {
        var copy = self
        copy.instanceNumber = number
        return copy
    }

    // MARK: - Patient Information Setters

    /// Sets the Patient ID
    /// - Parameter id: The patient ID
    /// - Returns: A new builder with the updated value
    public func withPatientID(_ id: String) -> Self {
        var copy = self
        copy.patientID = id
        return copy
    }

    /// Sets the Patient Name
    /// - Parameter name: The patient name
    /// - Returns: A new builder with the updated value
    public func withPatientName(_ name: String) -> Self {
        var copy = self
        copy.patientName = name
        return copy
    }

    /// Sets the Patient Birth Date
    /// - Parameter date: The birth date (YYYYMMDD format)
    /// - Returns: A new builder with the updated value
    public func withPatientBirthDate(_ date: String) -> Self {
        var copy = self
        copy.patientBirthDate = date
        return copy
    }

    /// Sets the Patient Sex
    /// - Parameter sex: The patient sex (M, F, O, or empty)
    /// - Returns: A new builder with the updated value
    public func withPatientSex(_ sex: String) -> Self {
        var copy = self
        copy.patientSex = sex
        return copy
    }

    // MARK: - Study Information Setters

    /// Sets the Study Date
    /// - Parameter date: The study date (YYYYMMDD format)
    /// - Returns: A new builder with the updated value
    public func withStudyDate(_ date: String) -> Self {
        var copy = self
        copy.studyDate = date
        return copy
    }

    /// Sets the Study Time
    /// - Parameter time: The study time (HHMMSS format)
    /// - Returns: A new builder with the updated value
    public func withStudyTime(_ time: String) -> Self {
        var copy = self
        copy.studyTime = time
        return copy
    }

    /// Sets the Study Description
    /// - Parameter description: The study description
    /// - Returns: A new builder with the updated value
    public func withStudyDescription(_ description: String) -> Self {
        var copy = self
        copy.studyDescription = description
        return copy
    }

    /// Sets the Accession Number
    /// - Parameter number: The accession number
    /// - Returns: A new builder with the updated value
    public func withAccessionNumber(_ number: String) -> Self {
        var copy = self
        copy.accessionNumber = number
        return copy
    }

    /// Sets the Referring Physician's Name
    /// - Parameter name: The referring physician's name
    /// - Returns: A new builder with the updated value
    public func withReferringPhysicianName(_ name: String) -> Self {
        var copy = self
        copy.referringPhysicianName = name
        return copy
    }

    // MARK: - Series Information Setters

    /// Sets the Series Number
    /// - Parameter number: The series number as string
    /// - Returns: A new builder with the updated value
    public func withSeriesNumber(_ number: String) -> Self {
        var copy = self
        copy.seriesNumber = number
        return copy
    }

    /// Sets the Series Description
    /// - Parameter description: The series description
    /// - Returns: A new builder with the updated value
    public func withSeriesDescription(_ description: String) -> Self {
        var copy = self
        copy.seriesDescription = description
        return copy
    }

    // MARK: - Document Information Setters

    /// Sets the Content Date
    /// - Parameter date: The content date (YYYYMMDD format)
    /// - Returns: A new builder with the updated value
    public func withContentDate(_ date: String) -> Self {
        var copy = self
        copy.contentDate = date
        return copy
    }

    /// Sets the Content Time
    /// - Parameter time: The content time (HHMMSS format)
    /// - Returns: A new builder with the updated value
    public func withContentTime(_ time: String) -> Self {
        var copy = self
        copy.contentTime = time
        return copy
    }

    /// Sets the Completion Flag
    /// - Parameter flag: The completion flag
    /// - Returns: A new builder with the updated value
    public func withCompletionFlag(_ flag: CompletionFlag) -> Self {
        var copy = self
        copy.completionFlag = flag
        return copy
    }

    /// Sets the Verification Flag
    /// - Parameter flag: The verification flag
    /// - Returns: A new builder with the updated value
    public func withVerificationFlag(_ flag: VerificationFlag) -> Self {
        var copy = self
        copy.verificationFlag = flag
        return copy
    }

    // MARK: - CAD Processing Information Setters

    /// Sets the CAD algorithm identification (TID 4019) written with every finding and
    /// derived detection.
    /// - Parameters:
    ///   - algorithmName: Name of the CAD algorithm (TID 4019 row 1)
    ///   - algorithmVersion: Version of the CAD algorithm (TID 4019 row 2)
    ///   - manufacturer: Manufacturer of the CAD system (TID 4019 row 2b)
    ///   - processingDateTime: Ignored; never written (no DATETIME in Table A.35.6-2)
    /// - Returns: A new builder with the updated values
    public func withCADProcessingSummary(
        algorithmName: String,
        algorithmVersion: String,
        manufacturer: String,
        processingDateTime: String? = nil
    ) -> Self {
        var copy = self
        copy.algorithmName = algorithmName
        copy.algorithmVersion = algorithmVersion
        copy.manufacturer = manufacturer
        copy.storedProcessingDateTime = processingDateTime
        return copy
    }

    /// Sets the language of the report (TID 1204, CID 5000 / CID 5001)
    public func withLanguage(_ language: CodedConcept, country: CodedConcept? = nil) -> Self {
        var copy = self
        copy.language = language
        copy.countryOfLanguage = country
        return copy
    }

    /// Adds an Image Library entry (TID 4020) with its acquisition context
    public func addImageLibraryEntry(_ entry: CADImageLibraryEntry) -> Self {
        var copy = self
        copy.imageLibraryEntries.append(entry)
        return copy
    }

    /// Adds a Detection Performed (TID 4017). `run.code` shall be from CID 6101 or CID 6102 (TID 4100 row 7).
    public func addDetectionPerformed(_ run: CADAlgorithmRun) -> Self {
        var copy = self
        copy.detectionsPerformed.append(run)
        return copy
    }

    /// Adds an Analysis Performed (TID 4018). `run.code` shall be from CID 6137 (TID 4100 row 9).
    public func addAnalysisPerformed(_ run: CADAlgorithmRun) -> Self {
        var copy = self
        copy.analysesPerformed.append(run)
        return copy
    }

    /// Sets (111064, DCM, "Summary of Detections") explicitly (TID 4100 row 6, CID 6042)
    public func withSummaryOfDetections(_ status: CADProcessingStatus) -> Self {
        var copy = self
        copy.summaryOfDetections = status
        return copy
    }

    /// Sets (111065, DCM, "Summary of Analyses") explicitly (TID 4100 row 8, CID 6042)
    public func withSummaryOfAnalyses(_ status: CADProcessingStatus) -> Self {
        var copy = self
        copy.summaryOfAnalyses = status
        return copy
    }

    /// Sets (111017, DCM, "CAD Processing and Findings Summary") explicitly (TID 4101 row 1, CID 6047)
    public func withProcessingAndFindingsSummary(_ summary: CADProcessingAndFindingsSummary) -> Self {
        var copy = self
        copy.processingAndFindingsSummary = summary
        return copy
    }

    // MARK: - CAD Findings Management

    /// Adds a CAD finding to the document
    /// - Parameter finding: The finding to add
    /// - Returns: A new builder with the added finding
    public func addFinding(_ finding: ChestCADFinding) -> Self {
        var copy = self
        copy.findings.append(finding)
        return copy
    }

    /// Adds a CAD finding to the document
    /// - Parameters:
    ///   - type: Type of finding (TID 4104 rows 1-2)
    ///   - probability: Certainty of Finding (0.0-1.0), written as (111012, DCM) in percent
    ///   - location: Spatial location of the finding (TID 4107)
    ///   - characteristics: Deprecated; not written (use `descriptors`, TID 4105)
    /// - Returns: A new builder with the added finding
    public func addFinding(
        type: ChestFindingType,
        probability: Double,
        location: ChestFindingLocation,
        characteristics: [CodedConcept]? = nil
    ) -> Self {
        let finding = ChestCADFinding(
            type: type,
            probability: probability,
            location: location,
            characteristics: characteristics
        )
        return addFinding(finding)
    }

    /// Clears all findings from the document
    /// - Returns: A new builder with all findings removed
    public func clearFindings() -> Self {
        var copy = self
        copy.findings = []
        return copy
    }

    // MARK: - Build

    /// Builds the Chest CAD SR document
    /// - Returns: The constructed SR document
    /// - Throws: BuildError if validation fails
    public func build() throws -> SRDocument {
        // Validate if requested
        if validateOnBuild {
            try validate()
        }

        // Generate UIDs if needed
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value

        // Build the root container
        let rootContainer = buildRootContainer()

        // Document title: TID 4100 row 1
        let documentTitle = CADSRCodes.chestCADReport

        // Create the SR document
        let document = SRDocument(
            sopClassUID: SRDocumentType.chestCADSR.sopClassUID,
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
            preliminaryFlag: nil,
            documentTitle: documentTitle,
            rootContent: rootContainer,
            patientBirthDate: patientBirthDate,
            patientSex: patientSex,
            referringPhysicianName: referringPhysicianName
        )

        return document
    }

    // MARK: - Derived values

    /// The algorithm identification (TID 4019) used for findings and derived detections
    public var algorithmIdentification: CADAlgorithmIdentification? {
        guard let algorithmName else { return nil }
        return CADAlgorithmIdentification(name: algorithmName, version: algorithmVersion ?? "", manufacturer: manufacturer)
    }

    /// Detections performed: the explicit ones, or one per distinct finding (TID 4017 row 1
    /// takes the modifier code from CID 6102 when there is one, else the CID 6101 code).
    public var effectiveDetectionsPerformed: [CADAlgorithmRun] {
        if !detectionsPerformed.isEmpty { return detectionsPerformed }
        var runs: [CADAlgorithmRun] = []
        for finding in findings {
            let code = finding.type.modifier ?? finding.type.singleImageFinding
            if let index = runs.firstIndex(where: { $0.code == code }) {
                var run = runs[index]
                if !run.images.contains(finding.location.imageReference) {
                    run.images.append(finding.location.imageReference)
                }
                runs[index] = run
            } else {
                runs.append(CADAlgorithmRun(code: code, algorithm: algorithmIdentification, images: [finding.location.imageReference]))
            }
        }
        return runs
    }

    /// The (111064, DCM, "Summary of Detections") value that will be written (CID 6042)
    public var effectiveSummaryOfDetections: CADProcessingStatus {
        summaryOfDetections ?? CADProcessingStatus.derived(from: effectiveDetectionsPerformed)
    }

    /// The (111065, DCM, "Summary of Analyses") value that will be written (CID 6042)
    public var effectiveSummaryOfAnalyses: CADProcessingStatus {
        summaryOfAnalyses ?? CADProcessingStatus.derived(from: analysesPerformed)
    }

    /// The (111017, DCM, "CAD Processing and Findings Summary") value that will be written (CID 6047)
    public var effectiveProcessingAndFindingsSummary: CADProcessingAndFindingsSummary {
        processingAndFindingsSummary ?? CADProcessingAndFindingsSummary.derived(
            detections: effectiveSummaryOfDetections,
            analyses: effectiveSummaryOfAnalyses,
            hasFindings: !findings.isEmpty
        )
    }

    /// The Image Library entries that will be written
    public var effectiveImageLibraryEntries: [CADImageLibraryEntry] {
        var entries = imageLibraryEntries
        let referenced = findings.map { $0.location.imageReference }
            + effectiveDetectionsPerformed.flatMap(\.images)
            + analysesPerformed.flatMap(\.images)
        for image in referenced where !entries.contains(where: { $0.image == image }) {
            entries.append(CADImageLibraryEntry(image: image))
        }
        return entries
    }

    // MARK: - Private Build Helpers

    private func buildRootContainer() -> ContainerContentItem {
        var children: [CADSRNode] = []

        // TID 4100 row 2: HAS CONCEPT MOD INCLUDE TID 1204 (M)
        children.append(CADSRNode.languageOfContent(language, country: countryOfLanguage))

        // TID 4100 rows 3-4: CONTAINS CONTAINER Image Library (U) with TID 4020 entries
        let images = effectiveImageLibraryEntries
        if !images.isEmpty {
            children.append(CADSRNode.imageLibrary(images))
        }

        // TID 4100 row 5: CONTAINS INCLUDE TID 4101 (M)
        children.append(buildFindingsSummary())

        // TID 4100 rows 6-7: Summary of Detections, INFERRED FROM TID 4015
        children.append(CADSRNode.summary(
            concept: CADSRCodes.summaryOfDetections,
            status: effectiveSummaryOfDetections,
            runs: effectiveDetectionsPerformed,
            successContainer: CADSRCodes.successfulDetections,
            failureContainer: CADSRCodes.failedDetections,
            runConcept: CADSRCodes.detectionPerformed,
            fallbackAlgorithm: algorithmIdentification
        ))

        // TID 4100 rows 8-9: Summary of Analyses, INFERRED FROM TID 4016
        children.append(CADSRNode.summary(
            concept: CADSRCodes.summaryOfAnalyses,
            status: effectiveSummaryOfAnalyses,
            runs: analysesPerformed,
            successContainer: CADSRCodes.successfulAnalyses,
            failureContainer: CADSRCodes.failedAnalyses,
            runConcept: CADSRCodes.analysisPerformed,
            fallbackAlgorithm: algorithmIdentification
        ))

        // TID 4100 row 1: root CONTAINER
        return CADSRNode.container(
            conceptName: CADSRCodes.chestCADReport,
            relationship: nil,
            templateIdentifier: "4100",
            children: children
        ).encodeRoot()
    }

    /// TID 4101: CODE (111017, DCM, "CAD Processing and Findings Summary") with the Single
    /// Image Findings INFERRED FROM it (row 3)
    private func buildFindingsSummary() -> CADSRNode {
        .leaf(
            AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.cadProcessingAndFindingsSummary,
                conceptCode: effectiveProcessingAndFindingsSummary.concept,
                relationshipType: .contains
            )),
            children: findings.map(buildSingleImageFinding)
        )
    }

    /// TID 4104: CODE (111059, DCM, "Single Image Finding") with its rows
    private func buildSingleImageFinding(_ finding: ChestCADFinding) -> CADSRNode {
        var children: [CADSRNode] = []

        // Row 2: HAS CONCEPT MOD CODE Single Image Finding Modifier (U, CID 6102)
        if let modifier = finding.type.modifier {
            children.append(.leaf(AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.singleImageFindingModifier, conceptCode: modifier, relationshipType: .hasConceptMod
            )), children: []))
        }

        // Row 6: HAS CONCEPT MOD CODE Rendering Intent (M, CID 6034)
        children.append(CADSRNode.renderingIntent(finding.renderingIntent))

        // Row 11: HAS OBS CONTEXT INCLUDE TID 4019 (M)
        if let algorithm = algorithmIdentification {
            children.append(contentsOf: CADSRNode.algorithmIdentification(algorithm, relationship: .hasObsContext))
        }

        // Row 12: HAS PROPERTIES NUM Certainty of Finding (U), percent
        children.append(CADSRNode.percent(concept: CADSRCodes.certaintyOfFinding, fraction: finding.probability, relationship: .hasProperties))

        // Row 14: HAS PROPERTIES INCLUDE TID 4107 (MC): unless the value is Image quality
        if finding.type.singleImageFinding.codeValue != CADSRCodes.imageQualityCode {
            children.append(contentsOf: CADSRNode.geometry(finding.location.geometry, relationship: .hasProperties))
        }

        // Row 18: HAS PROPERTIES INCLUDE TID 4105 (U): rows 1-15 CODE descriptors
        for descriptor in finding.descriptors where CADSRCodes.tid4105ConceptCodes.contains(descriptor.conceptName.codeValue) {
            children.append(.leaf(AnyContentItem(CodeContentItem(
                conceptName: descriptor.conceptName, conceptCode: descriptor.value, relationshipType: .hasProperties
            )), children: []))
        }

        // `characteristics` are not written: TID 4104 has no row for an uncoded characteristic.

        return .leaf(
            AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.singleImageFinding,
                conceptCode: finding.type.singleImageFinding,
                relationshipType: .inferredFrom
            )),
            children: children
        )
    }

    private func validate() throws {
        // TID 4019 row 1 (Algorithm Name) is Type M under every finding (TID 4104 row 11)
        if algorithmName == nil {
            throw BuildError.validationError(
                "CAD algorithm name should be specified (TID 4019 row 1 is mandatory)"
            )
        }

        // TID 4104 row 12: Certainty of Finding is 0-100 percent; the API takes 0-1
        for finding in findings {
            if finding.probability < 0.0 || finding.probability > 1.0 {
                throw BuildError.validationError(
                    "Finding probability must be between 0.0 and 1.0, got \(finding.probability)"
                )
            }
        }

        // TID 4100 rows 7 and 9: TID 4015/4016 shall be present unless Not Attempted
        if effectiveSummaryOfDetections != .notAttempted && effectiveDetectionsPerformed.isEmpty {
            throw BuildError.validationError(
                "Summary of Detections is \(effectiveSummaryOfDetections.concept.codeMeaning) but no Detection Performed (TID 4017) is available"
            )
        }
        if effectiveSummaryOfAnalyses != .notAttempted && analysesPerformed.isEmpty {
            throw BuildError.validationError(
                "Summary of Analyses is \(effectiveSummaryOfAnalyses.concept.codeMeaning) but no Analysis Performed (TID 4018) was added"
            )
        }
    }
}

// MARK: - Supporting Types

/// Represents a CAD finding in a Chest CAD SR document (one TID 4104 invocation)
public struct ChestCADFinding: Sendable, Equatable {
    /// Type of finding (TID 4104 rows 1-2)
    public let type: ChestFindingType

    /// Certainty of Finding (0.0-1.0); written as (111012, DCM, "Certainty of Finding") in
    /// percent (TID 4104 row 12)
    public let probability: Double

    /// Spatial location of the finding (TID 4107 via TID 4104 row 14)
    public let location: ChestFindingLocation

    /// Optional characteristics or descriptors. Not written: TID 4104 has no row for an
    /// uncoded characteristic; use ``descriptors`` (TID 4105).
    @available(*, deprecated, message: "not written: TID 4104 (Chest CAD Single Image Finding) has no row for uncoded characteristics; use descriptors (TID 4105)")
    public var characteristics: [CodedConcept]? { storedCharacteristics }
    private let storedCharacteristics: [CodedConcept]?

    /// Rendering Intent (TID 4104 row 6, CID 6034)
    public let renderingIntent: CADRenderingIntent

    /// TID 4105 descriptors (rows 1-15, e.g. (112025, DCM, "Size Descriptor") from CID 6118,
    /// (112013, DCM, "Location in Chest") from CID 6124)
    public let descriptors: [CADDescriptor]

    /// Creates a new CAD finding
    public init(
        type: ChestFindingType,
        probability: Double,
        location: ChestFindingLocation,
        characteristics: [CodedConcept]? = nil,
        renderingIntent: CADRenderingIntent = .presentationRequired,
        descriptors: [CADDescriptor] = []
    ) {
        self.type = type
        self.probability = probability
        self.location = location
        self.storedCharacteristics = characteristics
        self.renderingIntent = renderingIntent
        self.descriptors = descriptors
    }
}

/// Types of findings in chest CAD.
///
/// TID 4104 row 1 takes a CID 6101 value (e.g. (112033, DCM, "Abnormal opacity")) and row 2
/// a CID 6102 modifier (CID 6104 for opacities: Nodule, Mass, Tree-in-bud sign, ...).
public enum ChestFindingType: Sendable, Equatable {
    /// Abnormal opacity modified by (27925004, SCT, "Nodule") (CID 6104)
    case nodule

    /// Abnormal opacity modified by (4147007, SCT, "Mass") (CID 6104)
    case mass

    /// Lesion. No CID 6101/6102 term has this meaning; written as Abnormal opacity with a
    /// private (99DICOMKIT) modifier.
    @available(*, deprecated, message: "no CID 6101/6102 term for a generic lesion in PS3.16 2026a; written with a (99DICOMKIT) modifier. Use .nodule, .mass or .modified(finding:modifier:)")
    case lesion

    /// Pulmonary consolidation. No CID 6101/6102 term has this meaning; written as Abnormal
    /// opacity with a private (99DICOMKIT) modifier.
    @available(*, deprecated, message: "no CID 6101/6102 term for pulmonary consolidation in PS3.16 2026a; written with a (99DICOMKIT) modifier. Use .modified(finding:modifier:)")
    case consolidation

    /// Abnormal opacity modified by (112127, DCM, "Tree-in-bud sign") (CID 6104)
    case treeInBud

    /// Custom finding: the Single Image Finding value itself (shall be from CID 6101)
    case custom(CodedConcept)

    /// A CID 6101 finding with a CID 6102 modifier
    case modified(finding: CodedConcept, modifier: CodedConcept)

    /// The value of TID 4104 row 1 (CID 6101)
    public var singleImageFinding: CodedConcept {
        switch self {
        case .custom(let concept): return concept
        case .modified(let finding, _): return finding
        default: return CADSRCodes.abnormalOpacity
        }
    }

    /// The value of TID 4104 row 2 (CID 6102), if any
    public var modifier: CodedConcept? {
        switch self {
        case .nodule:
            return CodedConcept(codeValue: "27925004", codingSchemeDesignator: "SCT", codeMeaning: "Nodule")
        case .mass:
            return CodedConcept(codeValue: "4147007", codingSchemeDesignator: "SCT", codeMeaning: "Mass")
        case .treeInBud:
            return CodedConcept(codeValue: "112127", codingSchemeDesignator: "DCM", codeMeaning: "Tree-in-bud sign")
        case .custom:
            return nil
        case .modified(_, let modifier):
            return modifier
        default:
            // .lesion / .consolidation (deprecated): no CID 6102 term, private scheme
            return concept
        }
    }

    /// The most specific coded concept for this finding type: the modifier when there is one,
    /// else the Single Image Finding value
    public var concept: CodedConcept {
        switch self {
        case .nodule, .mass, .treeInBud, .modified:
            return modifier ?? singleImageFinding
        case .custom(let concept):
            return concept
        default:
            // .lesion / .consolidation are deprecated; matching them by pattern would warn,
            // so the payload-free case name is used instead.
            if String(describing: self) == "consolidation" {
                return CodedConcept(codeValue: "PULMONARY_CONSOLIDATION", codingSchemeDesignator: "99DICOMKIT", codeMeaning: "Pulmonary consolidation")
            }
            return CodedConcept(codeValue: "LESION", codingSchemeDesignator: "99DICOMKIT", codeMeaning: "Lesion")
        }
    }
}

/// Spatial location of a chest finding
public enum ChestFindingLocation: Sendable, Equatable {
    /// Point location (x, y coordinates)
    case point2D(x: Double, y: Double, imageReference: ImageReference)

    /// Region of interest (polygon defined by points)
    case roi2D(points: [Double], imageReference: ImageReference)

    /// Circular region (center x, y, radius)
    case circle2D(centerX: Double, centerY: Double, radius: Double, imageReference: ImageReference)

    /// The referenced image
    public var imageReference: ImageReference {
        switch self {
        case .point2D(_, _, let ref), .roi2D(_, let ref), .circle2D(_, _, _, let ref):
            return ref
        }
    }

    /// The TID 4107 geometry: Center (row 1, POINT) and optional Outline (row 4)
    var geometry: CADGeometry {
        switch self {
        case .point2D(let x, let y, let ref):
            return FindingLocation.point2D(x: x, y: y, imageReference: ref).geometry
        case .roi2D(let points, let ref):
            return FindingLocation.roi2D(points: points, imageReference: ref).geometry
        case .circle2D(let cx, let cy, let r, let ref):
            return FindingLocation.circle2D(centerX: cx, centerY: cy, radius: r, imageReference: ref).geometry
        }
    }
}
