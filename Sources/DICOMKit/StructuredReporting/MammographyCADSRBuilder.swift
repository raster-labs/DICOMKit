// NEMA-verified: 2026a, checked 2026-09-29 — content tree built row by row from PS3.16 2026a TID 4000, 1204, 4020, 4001, 4003, 4006, 4011, 4015, 4017, 4016, 4018, 4019, 4021; values from CID 6014/6015, 6034, 6042, 6043, 6047, 6022/6023, 4014, 4015; codes checked in Table D-1; value types per PS3.3 Table A.35.5-2 (no DATETIME). Children of non-CONTAINER nodes are nested in their Content Sequence per PS3.3 Table C.17-6 (D31, see CADSRNode).
/// Mammography CAD SR Document Builder
///
/// Provides a specialized fluent API for creating DICOM Mammography Computer-Aided Detection (CAD)
/// Structured Report documents. These documents encode the results of CAD analysis algorithms
/// that detect and characterize potential findings in mammography images.
///
/// Reference: PS3.3 Section A.35.5 - Mammography CAD SR IOD (Table A.35.5-2 relationship constraints)
/// Reference: PS3.16 TID 4000 - Mammography CAD Document Root
/// Reference: PS3.16 TID 4001 - Mammography CAD Overall Impression/Recommendation
/// Reference: PS3.16 TID 4003 - Mammography CAD Individual Impression/Recommendation
/// Reference: PS3.16 TID 4006 - Mammography CAD Single Image Finding
/// Reference: PS3.16 TID 4015/4017 - CAD Detections Performed / CAD Detection Performed
/// Reference: PS3.16 TID 4016/4018 - CAD Analyses Performed / CAD Analysis Performed
/// Reference: PS3.16 TID 4019 - Algorithm Identification
/// Reference: PS3.16 TID 4020 - CAD Image Library Entry
/// Reference: PS3.16 TID 4021 - Mammography CAD Geometry

import Foundation
import DICOMCore

/// Specialized builder for creating DICOM Mammography CAD SR documents
///
/// The content tree follows PS3.16 TID 4000 (Mammography CAD Document Root):
///
/// ```
/// CONTAINER (111036, DCM, "Mammography CAD Report")                       TID 4000 row 1
///  ├ HAS CONCEPT MOD CODE (121049, DCM, "Language of Content Item and Descendants")  TID 1204
///  ├ CONTAINS CONTAINER (111028, DCM, "Image Library")                     row 3
///  │   └ CONTAINS IMAGE [+ HAS ACQ CONTEXT laterality, view, ...]           TID 4020
///  ├ CONTAINS CODE (111017, DCM, "CAD Processing and Findings Summary")    TID 4001 row 1, CID 6047
///  │   └ INFERRED FROM CONTAINER (111034, DCM, "Individual Impression/Recommendation")  TID 4003
///  │       ├ HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent")         CID 6034
///  │       └ CONTAINS CODE (111059, DCM, "Single Image Finding")            TID 4006, CID 6014
///  │           ├ HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent")
///  │           ├ HAS PROPERTIES TEXT (111001, DCM, "Algorithm Name") ...    TID 4019
///  │           ├ HAS PROPERTIES NUM (111047, DCM, "Probability of cancer")  %
///  │           └ HAS PROPERTIES SCOORD (111010, DCM, "Center") ─ SELECTED FROM IMAGE  TID 4021
///  ├ CONTAINS CODE (111064, DCM, "Summary of Detections")                  CID 6042
///  │   └ INFERRED FROM CONTAINER (111063, DCM, "Successful Detections")     TID 4015
///  │       └ CONTAINS CODE (111022, DCM, "Detection Performed")             TID 4017
///  └ CONTAINS CODE (111065, DCM, "Summary of Analyses")                    CID 6042
///      └ INFERRED FROM CONTAINER (111062, DCM, "Successful Analyses")       TID 4016/4018
/// ```
///
/// Example:
/// ```swift
/// let document = try MammographyCADSRBuilder()
///     .withPatientID("12345")
///     .withPatientName("Doe^Jane")
///     .withCADProcessingSummary(
///         algorithmName: "MammoCAD v2.1",
///         algorithmVersion: "2.1.0",
///         manufacturer: "Example Medical Systems"
///     )
///     .addFinding(
///         type: .mass,
///         probability: 0.85,
///         location: .point2D(x: 128.5, y: 256.3, imageReference: imageRef)
///     )
///     .build()
/// ```
///
/// ## Nesting
/// Where a template row hangs children under a CODE, IMAGE or SCOORD (for example TID 4006
/// rows 2-8 under the Single Image Finding CODE, TID 4020 rows 2-12 under the IMAGE, or
/// TID 4021 row 2 under the Center SCOORD) the children are written in that item's Content
/// Sequence (PS3.3 Table C.17-6). Documents written before 2026-09-29 carried them as the
/// siblings that follow the item; ``CADFindings`` reads both forms. By-reference rows
/// (R-SELECTED FROM, R-INFERRED FROM) are written by value (SELECTED FROM, INFERRED FROM).
///
/// ## Supported Content
/// Mammography CAD SR documents support the value types of PS3.3 Table A.35.5-2:
/// TEXT, CODE, NUM, DATE, TIME, UIDREF, PNAME, COMPOSITE, IMAGE, SCOORD, CONTAINER
/// (DATETIME is not permitted).
public struct MammographyCADSRBuilder: Sendable {

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

    /// CAD algorithm name (TID 4019 row 1, (111001, DCM, "Algorithm Name"))
    public private(set) var algorithmName: String?

    /// CAD algorithm version (TID 4019 row 2, (111003, DCM, "Algorithm Version"))
    public private(set) var algorithmVersion: String?

    /// Manufacturer of the CAD system (TID 4019 row 2b, (122405, DCM, "Algorithm Manufacturer"))
    public private(set) var manufacturer: String?

    /// Processing date/time. Never written: TID 4019 has no date/time row and PS3.3
    /// Table A.35.5-2 permits no DATETIME content item in a Mammography CAD SR.
    @available(*, deprecated, message: "not written: TID 4019 (Algorithm Identification) has no date/time row and PS3.3 Table A.35.5-2 permits no DATETIME item in a Mammography CAD SR")
    public var processingDateTime: String? { storedProcessingDateTime }
    private var storedProcessingDateTime: String?

    /// Language of the report (TID 4000 row 2 / TID 1204 row 1, CID 5000: RFC 5646 tags).
    /// Defaults to ("en", RFC5646, "English").
    public private(set) var language: CodedConcept = CADSRDefaults.english

    /// Country of language (TID 1204 row 2, CID 5001)
    public private(set) var countryOfLanguage: CodedConcept?

    /// Explicit Image Library entries (TID 4000 rows 3-4 / TID 4020). Images referenced by
    /// findings or algorithm runs that are not listed here are added as plain IMAGE entries.
    public private(set) var imageLibraryEntries: [CADImageLibraryEntry] = []

    /// Explicit detections performed (TID 4015 / TID 4017). When empty, one Detection Performed
    /// per distinct finding type is derived from ``findings`` using the builder's algorithm.
    public private(set) var detectionsPerformed: [CADAlgorithmRun] = []

    /// Analyses performed (TID 4016 / TID 4018, CID 6043)
    public private(set) var analysesPerformed: [CADAlgorithmRun] = []

    /// Explicit value for (111064, DCM, "Summary of Detections") (CID 6042); derived when nil
    public private(set) var summaryOfDetections: CADProcessingStatus?

    /// Explicit value for (111065, DCM, "Summary of Analyses") (CID 6042); derived when nil
    public private(set) var summaryOfAnalyses: CADProcessingStatus?

    /// Explicit value for (111017, DCM, "CAD Processing and Findings Summary") (CID 6047);
    /// derived when nil
    public private(set) var processingAndFindingsSummary: CADProcessingAndFindingsSummary?

    // MARK: - CAD Findings

    /// Detected CAD findings
    public private(set) var findings: [CADFinding] = []

    // MARK: - Initialization

    /// Creates a new Mammography CAD SR document builder
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
    /// - Parameter date: The content date (YYYYMMDD format, or nil for current date)
    /// - Returns: A new builder with the updated value
    public func withContentDate(_ date: String?) -> Self {
        var copy = self
        copy.contentDate = date
        return copy
    }

    /// Sets the Content Time
    /// - Parameter time: The content time (HHMMSS format, or nil for current time)
    /// - Returns: A new builder with the updated value
    public func withContentTime(_ time: String?) -> Self {
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

    // MARK: - CAD Processing Setters

    /// Sets the CAD algorithm identification (TID 4019) written with every finding and
    /// derived detection.
    /// - Parameters:
    ///   - algorithmName: Name of the CAD algorithm (TID 4019 row 1)
    ///   - algorithmVersion: Version of the CAD algorithm (TID 4019 row 2)
    ///   - manufacturer: Manufacturer of the CAD system (TID 4019 row 2b)
    ///   - processingDateTime: Ignored; never written (no DATETIME in Table A.35.5-2)
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
    /// - Parameters:
    ///   - language: RFC 5646 language tag, e.g. ("en", RFC5646, "English")
    ///   - country: Optional country of language (CID 5001)
    /// - Returns: A new builder with the updated values
    public func withLanguage(_ language: CodedConcept, country: CodedConcept? = nil) -> Self {
        var copy = self
        copy.language = language
        copy.countryOfLanguage = country
        return copy
    }

    /// Adds an Image Library entry (TID 4020) with its acquisition context
    /// - Parameter entry: The entry
    /// - Returns: A new builder with the entry added
    public func addImageLibraryEntry(_ entry: CADImageLibraryEntry) -> Self {
        var copy = self
        copy.imageLibraryEntries.append(entry)
        return copy
    }

    /// Adds a Detection Performed (TID 4017). `run.code` shall be from CID 6014 (TID 4000 row 7).
    /// - Parameter run: The detection
    /// - Returns: A new builder with the detection added
    public func addDetectionPerformed(_ run: CADAlgorithmRun) -> Self {
        var copy = self
        copy.detectionsPerformed.append(run)
        return copy
    }

    /// Adds an Analysis Performed (TID 4018). `run.code` shall be from CID 6043 (TID 4000 row 9).
    /// - Parameter run: The analysis
    /// - Returns: A new builder with the analysis added
    public func addAnalysisPerformed(_ run: CADAlgorithmRun) -> Self {
        var copy = self
        copy.analysesPerformed.append(run)
        return copy
    }

    /// Sets (111064, DCM, "Summary of Detections") explicitly (TID 4000 row 6, CID 6042)
    public func withSummaryOfDetections(_ status: CADProcessingStatus) -> Self {
        var copy = self
        copy.summaryOfDetections = status
        return copy
    }

    /// Sets (111065, DCM, "Summary of Analyses") explicitly (TID 4000 row 8, CID 6042)
    public func withSummaryOfAnalyses(_ status: CADProcessingStatus) -> Self {
        var copy = self
        copy.summaryOfAnalyses = status
        return copy
    }

    /// Sets (111017, DCM, "CAD Processing and Findings Summary") explicitly (TID 4001 row 1, CID 6047)
    public func withProcessingAndFindingsSummary(_ summary: CADProcessingAndFindingsSummary) -> Self {
        var copy = self
        copy.processingAndFindingsSummary = summary
        return copy
    }

    // MARK: - Finding Management

    /// Adds a CAD finding to the document
    /// - Parameter finding: The CAD finding to add
    /// - Returns: A new builder with the finding added
    public func addFinding(_ finding: CADFinding) -> Self {
        var copy = self
        copy.findings.append(finding)
        return copy
    }

    /// Adds a CAD finding with detailed parameters
    /// - Parameters:
    ///   - type: The type of finding (CID 6014)
    ///   - probability: Probability of cancer (0.0-1.0), written as (111047, DCM) in percent
    ///   - location: Spatial location of the finding (TID 4021)
    ///   - characteristics: Deprecated; not written (no TID 4006 row for uncoded characteristics)
    /// - Returns: A new builder with the finding added
    public func addFinding(
        type: FindingType,
        probability: Double,
        location: FindingLocation,
        characteristics: [CodedConcept]? = nil
    ) -> Self {
        let finding = CADFinding(
            type: type,
            probability: probability,
            location: location,
            characteristics: characteristics
        )
        return addFinding(finding)
    }

    /// Removes all findings
    /// - Returns: A new builder with findings cleared
    public func clearFindings() -> Self {
        var copy = self
        copy.findings.removeAll()
        return copy
    }

    // MARK: - Build

    /// Builds the Mammography CAD SR document
    /// - Returns: The constructed SRDocument
    /// - Throws: BuildError if validation fails
    public func build() throws -> SRDocument {
        // Validate if required
        if validateOnBuild {
            try validate()
        }

        // Generate UIDs if needed
        let finalSOPInstanceUID = sopInstanceUID ?? UIDGenerator.generateUID().value
        let finalStudyInstanceUID = studyInstanceUID ?? UIDGenerator.generateUID().value
        let finalSeriesInstanceUID = seriesInstanceUID ?? UIDGenerator.generateUID().value

        // Build the root container
        let rootContainer = buildRootContainer()

        // Document title: TID 4000 row 1
        let documentTitle = CADSRCodes.mammographyCADReport

        // Create the SR document
        let document = SRDocument(
            sopClassUID: SRDocumentType.mammographyCADSR.sopClassUID,
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

    /// Detections performed: the explicit ones, or one per distinct finding type (TID 4017 row 1
    /// takes the CID 6014 finding code) referencing the images the findings were detected on.
    public var effectiveDetectionsPerformed: [CADAlgorithmRun] {
        if !detectionsPerformed.isEmpty { return detectionsPerformed }
        var runs: [CADAlgorithmRun] = []
        for finding in findings {
            let code = finding.type.concept
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

    /// The Image Library entries that will be written: the explicit ones plus a plain entry for
    /// every other image referenced by a finding or an algorithm run.
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

    // MARK: - Private Helpers

    private func buildRootContainer() -> ContainerContentItem {
        var children: [CADSRNode] = []

        // TID 4000 row 2: HAS CONCEPT MOD INCLUDE TID 1204
        children.append(CADSRNode.languageOfContent(language, country: countryOfLanguage))

        // TID 4000 rows 3-4: CONTAINS CONTAINER Image Library with TID 4020 entries (M, 1-n)
        children.append(CADSRNode.imageLibrary(effectiveImageLibraryEntries))

        // TID 4000 row 5: CONTAINS INCLUDE TID 4001
        children.append(buildProcessingAndFindingsSummary())

        // TID 4000 rows 6-7: Summary of Detections, INFERRED FROM TID 4015
        children.append(CADSRNode.summary(
            concept: CADSRCodes.summaryOfDetections,
            status: effectiveSummaryOfDetections,
            runs: effectiveDetectionsPerformed,
            successContainer: CADSRCodes.successfulDetections,
            failureContainer: CADSRCodes.failedDetections,
            runConcept: CADSRCodes.detectionPerformed,
            fallbackAlgorithm: algorithmIdentification
        ))

        // TID 4000 rows 8-9: Summary of Analyses, INFERRED FROM TID 4016
        children.append(CADSRNode.summary(
            concept: CADSRCodes.summaryOfAnalyses,
            status: effectiveSummaryOfAnalyses,
            runs: analysesPerformed,
            successContainer: CADSRCodes.successfulAnalyses,
            failureContainer: CADSRCodes.failedAnalyses,
            runConcept: CADSRCodes.analysisPerformed,
            fallbackAlgorithm: algorithmIdentification
        ))

        // TID 4000 row 1: root CONTAINER
        return CADSRNode.container(
            conceptName: CADSRCodes.mammographyCADReport,
            relationship: nil,
            templateIdentifier: "4000",
            children: children
        ).encodeRoot()
    }

    /// TID 4001: CODE (111017, DCM, "CAD Processing and Findings Summary") with the
    /// Individual Impression/Recommendation containers INFERRED FROM it (row 3).
    private func buildProcessingAndFindingsSummary() -> CADSRNode {
        var impressions: [CADSRNode] = []
        for finding in findings {
            impressions.append(buildIndividualImpression(finding))
        }
        return .leaf(
            AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.cadProcessingAndFindingsSummary,
                conceptCode: effectiveProcessingAndFindingsSummary.concept,
                relationshipType: .contains
            )),
            children: impressions
        )
    }

    /// TID 4003: CONTAINER (111034, DCM, "Individual Impression/Recommendation")
    private func buildIndividualImpression(_ finding: CADFinding) -> CADSRNode {
        .container(
            conceptName: CADSRCodes.individualImpressionRecommendation,
            relationship: .inferredFrom,
            children: [
                // Row 2: HAS CONCEPT MOD CODE Rendering Intent (M)
                CADSRNode.renderingIntent(finding.renderingIntent),
                // Row 5: CONTAINS INCLUDE TID 4006
                buildSingleImageFinding(finding)
            ]
        )
    }

    /// TID 4006: CODE (111059, DCM, "Single Image Finding") with its property rows
    private func buildSingleImageFinding(_ finding: CADFinding) -> CADSRNode {
        var children: [CADSRNode] = []
        let typeCode = finding.type.concept.codeValue

        // Row 2: HAS CONCEPT MOD CODE Rendering Intent (M)
        children.append(CADSRNode.renderingIntent(finding.renderingIntent))

        // Row 5: HAS PROPERTIES INCLUDE TID 4019 (M)
        if let algorithm = algorithmIdentification {
            children.append(contentsOf: CADSRNode.algorithmIdentification(algorithm, relationship: .hasProperties))
        }

        // Row 6: HAS PROPERTIES NUM Certainty of Finding (U), percent
        if let certainty = finding.certainty {
            children.append(CADSRNode.percent(concept: CADSRCodes.certaintyOfFinding, fraction: certainty, relationship: .hasProperties))
        }

        // Row 7: HAS PROPERTIES NUM Probability of cancer (UC): not for breast composition,
        // breast geometry, nipple, selected region, image quality or non-lesion parents
        if !CADSRCodes.noProbabilityOfCancerParents.contains(typeCode) {
            children.append(CADSRNode.percent(concept: CADSRCodes.probabilityOfCancer, fraction: finding.probability, relationship: .hasProperties))
        }

        // Row 8: HAS PROPERTIES INCLUDE TID 4021 (MC): not for breast composition, geometry, image quality
        if !CADSRCodes.noGeometryParents.contains(typeCode) {
            children.append(contentsOf: CADSRNode.geometry(finding.location.geometry, relationship: .hasProperties))
        }

        // Row 14: HAS PROPERTIES INCLUDE TID 4011 (UC): only for (129793001, SCT, "Mammography breast density")
        if typeCode == CADSRCodes.mammographyBreastDensityCode {
            for descriptor in finding.descriptors where CADSRCodes.tid4011ConceptCodes.contains(descriptor.conceptName.codeValue) {
                children.append(.leaf(AnyContentItem(CodeContentItem(
                    conceptName: descriptor.conceptName,
                    conceptCode: descriptor.value,
                    relationshipType: .hasProperties
                )), children: []))
            }
        }

        // `characteristics` are not written: TID 4006 has no row for an uncoded characteristic.

        return .leaf(
            AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.singleImageFinding,
                conceptCode: finding.type.concept,
                relationshipType: .contains
            )),
            children: children
        )
    }

    private func validate() throws {
        // TID 4019 row 1 (Algorithm Name) is Type M under every finding and detection
        if algorithmName == nil {
            throw BuildError.validationError(
                "CAD algorithm name should be specified (TID 4019 row 1 is mandatory)"
            )
        }

        for finding in findings {
            // Probability/certainty are 0-100 percent in TID 4006 rows 6-7; the API takes 0-1
            if finding.probability < 0.0 || finding.probability > 1.0 {
                throw BuildError.validationError(
                    "Finding probability must be between 0.0 and 1.0, got \(finding.probability)"
                )
            }
            if let certainty = finding.certainty, certainty < 0.0 || certainty > 1.0 {
                throw BuildError.validationError(
                    "Finding certainty must be between 0.0 and 1.0, got \(certainty)"
                )
            }
            // TID 4006 row 1: the value shall be from CID 6014
            if finding.type.isCompositeFeatureOnly {
                throw BuildError.validationError(
                    "\(finding.type.concept.codeMeaning) is a Composite Feature (CID 6017), not a Single Image Finding (CID 6014); use a composite-feature workflow or .custom"
                )
            }
        }

        // TID 4000 row 7: TID 4015 shall be present unless Summary of Detections is Not Attempted,
        // and TID 4015 rows 2/4 need at least one TID 4017.
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

/// Represents a CAD finding in a Mammography CAD SR document (one TID 4006 invocation)
public struct CADFinding: Sendable, Equatable {
    /// Type of finding (TID 4006 row 1, CID 6014)
    public let type: FindingType

    /// Probability of cancer (0.0-1.0); written as (111047, DCM, "Probability of cancer") in
    /// percent (TID 4006 row 7)
    public let probability: Double

    /// Spatial location of the finding (TID 4021 via TID 4006 row 8)
    public let location: FindingLocation

    /// Optional characteristics or descriptors. Not written: TID 4006 has no row for an
    /// uncoded characteristic; use ``descriptors`` (TID 4011) for density findings.
    @available(*, deprecated, message: "not written: TID 4006 (Mammography CAD Single Image Finding) has no row for uncoded characteristics; use descriptors (TID 4011)")
    public var characteristics: [CodedConcept]? { storedCharacteristics }
    private let storedCharacteristics: [CodedConcept]?

    /// Rendering Intent (TID 4006 row 2 / TID 4003 row 2, CID 6034)
    public let renderingIntent: CADRenderingIntent

    /// Certainty of Finding (0.0-1.0), written in percent (TID 4006 row 6)
    public let certainty: Double?

    /// TID 4011 descriptors (Lesion Density (111035, DCM), Shape (107644003, SCT),
    /// Margin (112233002, SCT)); written only when `type` is Mammography breast density
    /// (TID 4006 row 14)
    public let descriptors: [CADDescriptor]

    /// Creates a new CAD finding
    public init(
        type: FindingType,
        probability: Double,
        location: FindingLocation,
        characteristics: [CodedConcept]? = nil,
        renderingIntent: CADRenderingIntent = .presentationRequired,
        certainty: Double? = nil,
        descriptors: [CADDescriptor] = []
    ) {
        self.type = type
        self.probability = probability
        self.location = location
        self.storedCharacteristics = characteristics
        self.renderingIntent = renderingIntent
        self.certainty = certainty
        self.descriptors = descriptors
    }
}

/// Types of findings in mammography CAD (values of TID 4006 row 1, CID 6014 / CID 6015)
public enum FindingType: Sendable, Equatable {
    /// Mass, encoded as (129793001, SCT, "Mammography breast density") (CID 6015)
    case mass

    /// Calcification, encoded as (129770007, SCT, "Individual Calcification") (CID 6015)
    case calcification

    /// Architectural distortion (129792006, SCT) (CID 6015)
    case architecturalDistortion

    /// Asymmetry. (129790003, SCT, "Asymmetric breast tissue") is in CID 6017 (Composite
    /// Feature) only, not in CID 6014 (Single Image Finding); `build()` rejects it when
    /// validating.
    @available(*, deprecated, message: "(129790003, SCT, \"Asymmetric breast tissue\") is a CID 6017 Composite Feature, not a CID 6014 Single Image Finding (TID 4006 row 1)")
    case asymmetry

    /// Custom finding type (shall be from CID 6014)
    case custom(CodedConcept)

    /// The coded concept for this finding type (PS3.16 CID 6015 / CID 6017)
    public var concept: CodedConcept {
        switch self {
        case .mass:
            return CodedConcept(
                codeValue: "129793001",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Mammography breast density"
            )
        case .calcification:
            return CodedConcept(
                codeValue: "129770007",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Individual Calcification"
            )
        case .architecturalDistortion:
            return CodedConcept(
                codeValue: "129792006",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Architectural distortion of breast"
            )
        case .custom(let concept):
            return concept
        default:
            // .asymmetry (deprecated): CID 6017 (129790003, SCT, "Asymmetric breast tissue")
            return CodedConcept(
                codeValue: "129790003",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Asymmetric breast tissue"
            )
        }
    }

    /// True for values that CID 6017 lists as Composite Features and CID 6014 does not list
    var isCompositeFeatureOnly: Bool {
        ["129788004", "129789007", "129790003"].contains(concept.codeValue)
    }
}

/// Spatial location of a finding
public enum FindingLocation: Sendable, Equatable {
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

    /// The TID 4021 geometry: Center (row 1, POINT) and optional Outline (row 3)
    var geometry: CADGeometry {
        switch self {
        case .point2D(let x, let y, let ref):
            return CADGeometry(center: (Float(x), Float(y)), outline: nil, image: ref)
        case .roi2D(let points, let ref):
            let xs = stride(from: 0, to: points.count - 1, by: 2).map { points[$0] }
            let ys = stride(from: 1, to: points.count, by: 2).map { points[$0] }
            let cx = xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
            let cy = ys.isEmpty ? 0 : ys.reduce(0, +) / Double(ys.count)
            return CADGeometry(center: (Float(cx), Float(cy)), outline: (.polyline, points.map { Float($0) }), image: ref)
        case .circle2D(let cx, let cy, let r, let ref):
            // PS3.3 C.18.6.1.2: CIRCLE is two points, the centre and a point on the circumference.
            return CADGeometry(center: (Float(cx), Float(cy)), outline: (.circle, [Float(cx), Float(cy), Float(cx + r), Float(cy)]), image: ref)
        }
    }
}

/// TID 4021 / TID 4107 geometry: Center POINT plus optional Outline, both on one image
struct CADGeometry {
    let center: (Float, Float)
    let outline: (GraphicType, [Float])?
    let image: ImageReference
}

// MARK: - Shared CAD SR types

/// Rendering Intent (CID 6034)
public enum CADRenderingIntent: String, Sendable, Equatable, Hashable, CaseIterable {
    /// (111150, DCM)
    case presentationRequired = "111150"
    /// (111151, DCM)
    case presentationOptional = "111151"
    /// (111152, DCM)
    case notForPresentation = "111152"

    /// The CID 6034 code
    public var concept: CodedConcept {
        switch self {
        case .presentationRequired:
            return CodedConcept(codeValue: "111150", codingSchemeDesignator: "DCM", codeMeaning: "Presentation Required: Rendering device is expected to present")
        case .presentationOptional:
            return CodedConcept(codeValue: "111151", codingSchemeDesignator: "DCM", codeMeaning: "Presentation Optional: Rendering device may present")
        case .notForPresentation:
            return CodedConcept(codeValue: "111152", codingSchemeDesignator: "DCM", codeMeaning: "Not for Presentation: Rendering device expected not to present")
        }
    }

    /// The intent for a CID 6034 code, if it is one
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == "DCM", let intent = CADRenderingIntent(rawValue: concept.codeValue) else { return nil }
        self = intent
    }
}

/// Processing status of detections or analyses (CID 6042)
public enum CADProcessingStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    /// (111222, DCM)
    case succeeded = "111222"
    /// (111223, DCM)
    case partiallySucceeded = "111223"
    /// (111224, DCM)
    case failed = "111224"
    /// (111225, DCM)
    case notAttempted = "111225"

    /// The CID 6042 code
    public var concept: CodedConcept {
        switch self {
        case .succeeded: return CodedConcept(codeValue: "111222", codingSchemeDesignator: "DCM", codeMeaning: "Succeeded")
        case .partiallySucceeded: return CodedConcept(codeValue: "111223", codingSchemeDesignator: "DCM", codeMeaning: "Partially Succeeded")
        case .failed: return CodedConcept(codeValue: "111224", codingSchemeDesignator: "DCM", codeMeaning: "Failed")
        case .notAttempted: return CodedConcept(codeValue: "111225", codingSchemeDesignator: "DCM", codeMeaning: "Not Attempted")
        }
    }

    /// The status for a CID 6042 code, if it is one
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == "DCM", let status = CADProcessingStatus(rawValue: concept.codeValue) else { return nil }
        self = status
    }

    /// Not Attempted when there are no runs; Succeeded/Failed/Partially Succeeded from their outcomes
    static func derived(from runs: [CADAlgorithmRun]) -> CADProcessingStatus {
        guard !runs.isEmpty else { return .notAttempted }
        let succeeded = runs.filter(\.succeeded).count
        if succeeded == runs.count { return .succeeded }
        if succeeded == 0 { return .failed }
        return .partiallySucceeded
    }
}

/// Value of (111017, DCM, "CAD Processing and Findings Summary") (CID 6047)
public enum CADProcessingAndFindingsSummary: String, Sendable, Equatable, Hashable, CaseIterable {
    /// (111241, DCM)
    case allAlgorithmsSucceededWithoutFindings = "111241"
    /// (111242, DCM)
    case allAlgorithmsSucceededWithFindings = "111242"
    /// (111243, DCM)
    case notAllAlgorithmsSucceededWithoutFindings = "111243"
    /// (111244, DCM)
    case notAllAlgorithmsSucceededWithFindings = "111244"
    /// (111245, DCM)
    case noAlgorithmsSucceededWithoutFindings = "111245"

    /// The CID 6047 code
    public var concept: CodedConcept {
        switch self {
        case .allAlgorithmsSucceededWithoutFindings:
            return CodedConcept(codeValue: "111241", codingSchemeDesignator: "DCM", codeMeaning: "All algorithms succeeded; without findings")
        case .allAlgorithmsSucceededWithFindings:
            return CodedConcept(codeValue: "111242", codingSchemeDesignator: "DCM", codeMeaning: "All algorithms succeeded; with findings")
        case .notAllAlgorithmsSucceededWithoutFindings:
            return CodedConcept(codeValue: "111243", codingSchemeDesignator: "DCM", codeMeaning: "Not all algorithms succeeded; without findings")
        case .notAllAlgorithmsSucceededWithFindings:
            return CodedConcept(codeValue: "111244", codingSchemeDesignator: "DCM", codeMeaning: "Not all algorithms succeeded; with findings")
        case .noAlgorithmsSucceededWithoutFindings:
            return CodedConcept(codeValue: "111245", codingSchemeDesignator: "DCM", codeMeaning: "No algorithms succeeded; without findings")
        }
    }

    /// The summary for a CID 6047 code, if it is one
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == "DCM", let summary = CADProcessingAndFindingsSummary(rawValue: concept.codeValue) else { return nil }
        self = summary
    }

    static func derived(detections: CADProcessingStatus, analyses: CADProcessingStatus, hasFindings: Bool) -> CADProcessingAndFindingsSummary {
        let statuses = [detections, analyses]
        let anyFailure = statuses.contains { $0 == .failed || $0 == .partiallySucceeded }
        let anySuccess = statuses.contains { $0 == .succeeded || $0 == .partiallySucceeded }
        if hasFindings {
            return anyFailure ? .notAllAlgorithmsSucceededWithFindings : .allAlgorithmsSucceededWithFindings
        }
        if anyFailure && !anySuccess { return .noAlgorithmsSucceededWithoutFindings }
        return anyFailure ? .notAllAlgorithmsSucceededWithoutFindings : .allAlgorithmsSucceededWithoutFindings
    }
}

/// Algorithm Identification (TID 4019)
public struct CADAlgorithmIdentification: Sendable, Equatable, Hashable {
    /// (111001, DCM, "Algorithm Name") (row 1, M)
    public var name: String
    /// (111003, DCM, "Algorithm Version") (row 2, M)
    public var version: String
    /// (122405, DCM, "Algorithm Manufacturer") (row 2b, U)
    public var manufacturer: String?
    /// (111002, DCM, "Algorithm Parameters") (row 3, U, 1-n)
    public var parameters: [String]
    /// (111000, DCM, "Algorithm Family") (row 4, U)
    public var family: CodedConcept?

    public init(name: String, version: String, manufacturer: String? = nil, parameters: [String] = [], family: CodedConcept? = nil) {
        self.name = name
        self.version = version
        self.manufacturer = manufacturer
        self.parameters = parameters
        self.family = family
    }
}

/// One Detection Performed (TID 4017) or Analysis Performed (TID 4018)
public struct CADAlgorithmRun: Sendable, Equatable {
    /// Row 1 value: the detection code ($DetectionCode) or analysis code ($AnalysisCode)
    public var code: CodedConcept
    /// Row 2: TID 4019; the builder's algorithm is used when nil
    public var algorithm: CADAlgorithmIdentification?
    /// Row 3: HAS PROPERTIES IMAGE, the images processed
    public var images: [ImageReference]
    /// Row 5: HAS PROPERTIES UIDREF (112002, DCM, "Series Instance UID")
    public var seriesInstanceUIDs: [String]
    /// Whether the run succeeded (TID 4015/4016: Successful vs Failed container)
    public var succeeded: Bool

    public init(code: CodedConcept, algorithm: CADAlgorithmIdentification? = nil, images: [ImageReference] = [], seriesInstanceUIDs: [String] = [], succeeded: Bool = true) {
        self.code = code
        self.algorithm = algorithm
        self.images = images
        self.seriesInstanceUIDs = seriesInstanceUIDs
        self.succeeded = succeeded
    }
}

/// CAD Image Library Entry (TID 4020): an IMAGE with its acquisition context
public struct CADImageLibraryEntry: Sendable, Equatable {
    /// Row 1: the image
    public var image: ImageReference
    /// Row 2: (111027, DCM, "Image Laterality") (CID 6022 for mammography, CID 244 for chest)
    public var laterality: CodedConcept?
    /// Row 3: (111031, DCM, "Image View") (CID 4014 for mammography, CID 4010 for chest)
    public var view: CodedConcept?
    /// Row 4: (111032, DCM, "Image View Modifier") (CID 4015 / CID 4011)
    public var viewModifiers: [CodedConcept]
    /// Row 5: (111044, DCM, "Patient Orientation Row")
    public var patientOrientationRow: String?
    /// Row 6: (111043, DCM, "Patient Orientation Column")
    public var patientOrientationColumn: String?
    /// Row 7: (111060, DCM, "Study Date") (DA)
    public var studyDate: String?
    /// Row 8: (111061, DCM, "Study Time") (TM)
    public var studyTime: String?
    /// Row 9: (111018, DCM, "Content Date") (DA)
    public var contentDate: String?
    /// Row 10: (111019, DCM, "Content Time") (TM)
    public var contentTime: String?
    /// Row 11: (111026, DCM, "Horizontal Pixel Spacing") in (mm, UCUM, "millimeter")
    public var horizontalPixelSpacingMM: Double?
    /// Row 12: (111066, DCM, "Vertical Pixel Spacing") in (mm, UCUM, "millimeter")
    public var verticalPixelSpacingMM: Double?

    public init(
        image: ImageReference,
        laterality: CodedConcept? = nil,
        view: CodedConcept? = nil,
        viewModifiers: [CodedConcept] = [],
        patientOrientationRow: String? = nil,
        patientOrientationColumn: String? = nil,
        studyDate: String? = nil,
        studyTime: String? = nil,
        contentDate: String? = nil,
        contentTime: String? = nil,
        horizontalPixelSpacingMM: Double? = nil,
        verticalPixelSpacingMM: Double? = nil
    ) {
        self.image = image
        self.laterality = laterality
        self.view = view
        self.viewModifiers = viewModifiers
        self.patientOrientationRow = patientOrientationRow
        self.patientOrientationColumn = patientOrientationColumn
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.contentDate = contentDate
        self.contentTime = contentTime
        self.horizontalPixelSpacingMM = horizontalPixelSpacingMM
        self.verticalPixelSpacingMM = verticalPixelSpacingMM
    }
}

/// A coded descriptor of a finding: a concept name from TID 4011 (mammography) or TID 4105
/// (chest) with its value
public struct CADDescriptor: Sendable, Equatable, Hashable {
    /// The row's concept name, e.g. (112025, DCM, "Size Descriptor")
    public var conceptName: CodedConcept
    /// The value, from the row's context group
    public var value: CodedConcept

    public init(conceptName: CodedConcept, value: CodedConcept) {
        self.conceptName = conceptName
        self.value = value
    }
}

/// Defaults shared by the CAD SR builders
enum CADSRDefaults {
    /// CID 5000 is the RFC 5646 language tag scheme (Coding Scheme Designator RFC5646)
    static let english = CodedConcept(codeValue: "en", codingSchemeDesignator: "RFC5646", codeMeaning: "English")
}

/// Concept names and codes of the CAD templates, each checked against PS3.16 2026a Table D-1
enum CADSRCodes {
    static func dcm(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "DCM", codeMeaning: meaning)
    }

    // Document roots (TID 4000 row 1, TID 4100 row 1)
    static let mammographyCADReport = dcm("111036", "Mammography CAD Report")
    static let chestCADReport = dcm("112000", "Chest CAD Report")

    // TID 1204
    static let languageOfContentItemAndDescendants = dcm("121049", "Language of Content Item and Descendants")
    static let countryOfLanguage = dcm("121046", "Country of Language")

    // Image Library (TID 4000 row 3, TID 4020)
    static let imageLibrary = dcm("111028", "Image Library")
    static let imageLaterality = dcm("111027", "Image Laterality")
    static let imageView = dcm("111031", "Image View")
    static let imageViewModifier = dcm("111032", "Image View Modifier")
    static let patientOrientationRow = dcm("111044", "Patient Orientation Row")
    static let patientOrientationColumn = dcm("111043", "Patient Orientation Column")
    static let studyDate = dcm("111060", "Study Date")
    static let studyTime = dcm("111061", "Study Time")
    static let contentDate = dcm("111018", "Content Date")
    static let contentTime = dcm("111019", "Content Time")
    static let horizontalPixelSpacing = dcm("111026", "Horizontal Pixel Spacing")
    static let verticalPixelSpacing = dcm("111066", "Vertical Pixel Spacing")

    // TID 4001 / TID 4101 row 1, TID 4003
    static let cadProcessingAndFindingsSummary = dcm("111017", "CAD Processing and Findings Summary")
    static let individualImpressionRecommendation = dcm("111034", "Individual Impression/Recommendation")
    static let renderingIntent = dcm("111056", "Rendering Intent")

    // TID 4006 / TID 4104
    static let singleImageFinding = dcm("111059", "Single Image Finding")
    static let singleImageFindingModifier = dcm("112024", "Single Image Finding Modifier")
    static let certaintyOfFinding = dcm("111012", "Certainty of Finding")
    static let probabilityOfCancer = dcm("111047", "Probability of cancer")

    // TID 4021 / TID 4107
    static let center = dcm("111010", "Center")
    static let outline = dcm("111041", "Outline")

    // TID 4000 rows 6-9, TID 4015-4018
    static let summaryOfDetections = dcm("111064", "Summary of Detections")
    static let summaryOfAnalyses = dcm("111065", "Summary of Analyses")
    static let successfulDetections = dcm("111063", "Successful Detections")
    static let failedDetections = dcm("111025", "Failed Detections")
    static let successfulAnalyses = dcm("111062", "Successful Analyses")
    static let failedAnalyses = dcm("111024", "Failed Analyses")
    static let detectionPerformed = dcm("111022", "Detection Performed")
    static let analysisPerformed = dcm("111004", "Analysis Performed")
    static let seriesInstanceUID = dcm("112002", "Series Instance UID")

    // TID 4019
    static let algorithmName = dcm("111001", "Algorithm Name")
    static let algorithmVersion = dcm("111003", "Algorithm Version")
    static let algorithmManufacturer = dcm("122405", "Algorithm Manufacturer")
    static let algorithmParameters = dcm("111002", "Algorithm Parameters")
    static let algorithmFamily = dcm("111000", "Algorithm Family")

    // Units
    static let percent = CodedConcept(codeValue: "%", codingSchemeDesignator: "UCUM", codeMeaning: "Percent")
    static let millimeter = CodedConcept(codeValue: "mm", codingSchemeDesignator: "UCUM", codeMeaning: "millimeter")

    // TID 4006 conditions
    /// Row 7: no Probability of cancer for Breast composition, Breast geometry, Nipple,
    /// Selected region, Image quality, Non-lesion
    static let noProbabilityOfCancerParents: Set<String> = ["129715009", "111100", "24142002", "111099", "111101", "111102"]
    /// Row 8: no TID 4021 geometry for Breast composition, Breast geometry, Image quality
    static let noGeometryParents: Set<String> = ["129715009", "111100", "111101"]
    /// Row 14: TID 4011 only for (129793001, SCT, "Mammography breast density")
    static let mammographyBreastDensityCode = "129793001"
    /// TID 4011 rows 1-3 concept names: Lesion Density, Shape, Margin
    static let tid4011ConceptCodes: Set<String> = ["111035", "107644003", "112233002"]

    // Chest (TID 4104 / TID 4105)
    /// TID 4104 row 1 value (112033, DCM, "Abnormal opacity") (CID 6101)
    static let abnormalOpacity = dcm("112033", "Abnormal opacity")
    /// TID 4104 row 14: no TID 4107 geometry for (111101, DCM, "Image quality")
    static let imageQualityCode = "111101"
    /// TID 4105 rows 1-15 concept names
    static let tid4105ConceptCodes: Set<String> = [
        "112025", "112026", "112015", "112007", "112014", "112009", "112027", "112013",
        "272741003", "112006", "112028", "112008", "246112005", "112010", "112030"
    ]
}

// MARK: - Template tree encoder

/// A node of the logical template tree.
///
/// `encode()` nests the children of every node in its Content Sequence (0040,A730), each
/// keeping the relationship type its template row gives: the Document Relationship Macro
/// (PS3.3 Table C.17-6) applies to every content item, so a child row (">") under a CODE,
/// IMAGE or SCOORD row is a child of that item (e.g. TID 4006 rows 2-8, TID 4021 row 2).
/// Until 2026-09-29 (D31) the children of a non-CONTAINER node were written as the siblings
/// that immediately follow it; ``CADFindings`` still reads that form.
indirect enum CADSRNode {
    /// A non-container item with its template children
    case leaf(AnyContentItem, children: [CADSRNode])
    /// A CONTAINER item
    case container(conceptName: CodedConcept, relationship: RelationshipType?, templateIdentifier: String? = nil, children: [CADSRNode])

    /// Encodes this node as one content item with its children nested (see the type comment)
    func encode() -> [AnyContentItem] {
        switch self {
        case .leaf(let item, let children):
            return [item.addingContentItems(children.flatMap { $0.encode() })]
        case .container:
            return [AnyContentItem(encodeRoot())]
        }
    }

    /// Encodes a container node as a `ContainerContentItem`
    func encodeRoot() -> ContainerContentItem {
        guard case .container(let conceptName, let relationship, let templateIdentifier, let children) = self else {
            preconditionFailure("encodeRoot on a leaf node")
        }
        return ContainerContentItem(
            conceptName: conceptName,
            continuityOfContent: .separate,
            contentItems: children.flatMap { $0.encode() },
            templateIdentifier: templateIdentifier,
            mappingResource: templateIdentifier == nil ? nil : "DCMR",
            relationshipType: relationship
        )
    }

    // MARK: Template fragments shared by the mammography and chest builders

    /// TID 1204: HAS CONCEPT MOD CODE Language of Content Item and Descendants [+ Country of Language]
    static func languageOfContent(_ language: CodedConcept, country: CodedConcept?) -> CADSRNode {
        var children: [CADSRNode] = []
        if let country {
            children.append(.leaf(AnyContentItem(CodeContentItem(
                conceptName: CADSRCodes.countryOfLanguage, conceptCode: country, relationshipType: .hasConceptMod
            )), children: []))
        }
        return .leaf(AnyContentItem(CodeContentItem(
            conceptName: CADSRCodes.languageOfContentItemAndDescendants, conceptCode: language, relationshipType: .hasConceptMod
        )), children: children)
    }

    /// CONTAINS CONTAINER (111028, DCM, "Image Library") with one TID 4020 entry per image
    static func imageLibrary(_ entries: [CADImageLibraryEntry]) -> CADSRNode {
        .container(conceptName: CADSRCodes.imageLibrary, relationship: .contains, children: entries.map(imageLibraryEntry))
    }

    /// TID 4020: IMAGE with HAS ACQ CONTEXT rows 2-12
    static func imageLibraryEntry(_ entry: CADImageLibraryEntry) -> CADSRNode {
        var children: [CADSRNode] = []
        func code(_ name: CodedConcept, _ value: CodedConcept, _ rel: RelationshipType = .hasAcqContext, children: [CADSRNode] = []) -> CADSRNode {
            .leaf(AnyContentItem(CodeContentItem(conceptName: name, conceptCode: value, relationshipType: rel)), children: children)
        }
        func text(_ name: CodedConcept, _ value: String) -> CADSRNode {
            .leaf(AnyContentItem(TextContentItem(conceptName: name, textValue: value, relationshipType: .hasAcqContext)), children: [])
        }
        if let laterality = entry.laterality { children.append(code(CADSRCodes.imageLaterality, laterality)) }
        if let view = entry.view {
            // Row 4: HAS CONCEPT MOD CODE Image View Modifier under the Image View
            let modifiers = entry.viewModifiers.map { code(CADSRCodes.imageViewModifier, $0, .hasConceptMod) }
            children.append(code(CADSRCodes.imageView, view, children: modifiers))
        }
        if let row = entry.patientOrientationRow { children.append(text(CADSRCodes.patientOrientationRow, row)) }
        if let column = entry.patientOrientationColumn { children.append(text(CADSRCodes.patientOrientationColumn, column)) }
        if let date = entry.studyDate {
            children.append(.leaf(AnyContentItem(DateContentItem(conceptName: CADSRCodes.studyDate, dateValue: date, relationshipType: .hasAcqContext)), children: []))
        }
        if let time = entry.studyTime {
            children.append(.leaf(AnyContentItem(TimeContentItem(conceptName: CADSRCodes.studyTime, timeValue: time, relationshipType: .hasAcqContext)), children: []))
        }
        if let date = entry.contentDate {
            children.append(.leaf(AnyContentItem(DateContentItem(conceptName: CADSRCodes.contentDate, dateValue: date, relationshipType: .hasAcqContext)), children: []))
        }
        if let time = entry.contentTime {
            children.append(.leaf(AnyContentItem(TimeContentItem(conceptName: CADSRCodes.contentTime, timeValue: time, relationshipType: .hasAcqContext)), children: []))
        }
        if let spacing = entry.horizontalPixelSpacingMM {
            children.append(.leaf(AnyContentItem(NumericContentItem(conceptName: CADSRCodes.horizontalPixelSpacing, value: spacing, units: CADSRCodes.millimeter, relationshipType: .hasAcqContext)), children: []))
        }
        if let spacing = entry.verticalPixelSpacingMM {
            children.append(.leaf(AnyContentItem(NumericContentItem(conceptName: CADSRCodes.verticalPixelSpacing, value: spacing, units: CADSRCodes.millimeter, relationshipType: .hasAcqContext)), children: []))
        }
        return .leaf(AnyContentItem(ImageContentItem(conceptName: nil, imageReference: entry.image, relationshipType: .contains)), children: children)
    }

    /// HAS CONCEPT MOD CODE (111056, DCM, "Rendering Intent") (CID 6034)
    static func renderingIntent(_ intent: CADRenderingIntent) -> CADSRNode {
        .leaf(AnyContentItem(CodeContentItem(
            conceptName: CADSRCodes.renderingIntent, conceptCode: intent.concept, relationshipType: .hasConceptMod
        )), children: [])
    }

    /// TID 4019 rows 1, 2, 2b, 3, 4 with the relationship the including row gives
    static func algorithmIdentification(_ algorithm: CADAlgorithmIdentification, relationship: RelationshipType) -> [CADSRNode] {
        var nodes: [CADSRNode] = [
            .leaf(AnyContentItem(TextContentItem(conceptName: CADSRCodes.algorithmName, textValue: algorithm.name, relationshipType: relationship)), children: []),
            .leaf(AnyContentItem(TextContentItem(conceptName: CADSRCodes.algorithmVersion, textValue: algorithm.version, relationshipType: relationship)), children: [])
        ]
        if let manufacturer = algorithm.manufacturer {
            nodes.append(.leaf(AnyContentItem(TextContentItem(conceptName: CADSRCodes.algorithmManufacturer, textValue: manufacturer, relationshipType: relationship)), children: []))
        }
        for parameter in algorithm.parameters {
            nodes.append(.leaf(AnyContentItem(TextContentItem(conceptName: CADSRCodes.algorithmParameters, textValue: parameter, relationshipType: relationship)), children: []))
        }
        if let family = algorithm.family {
            nodes.append(.leaf(AnyContentItem(CodeContentItem(conceptName: CADSRCodes.algorithmFamily, conceptCode: family, relationshipType: relationship)), children: []))
        }
        return nodes
    }

    /// NUM in (%, UCUM, "Percent"), 0-100, from a 0-1 fraction
    static func percent(concept: CodedConcept, fraction: Double, relationship: RelationshipType) -> CADSRNode {
        .leaf(AnyContentItem(NumericContentItem(
            conceptName: concept, value: fraction * 100, units: CADSRCodes.percent, relationshipType: relationship
        )), children: [])
    }

    /// TID 4021 / TID 4107: SCOORD Center (POINT) and optional SCOORD Outline, each SELECTED FROM
    /// the image (by value; the by-reference R-SELECTED FROM rows are not representable)
    static func geometry(_ geometry: CADGeometry, relationship: RelationshipType) -> [CADSRNode] {
        let image = CADSRNode.leaf(AnyContentItem(ImageContentItem(conceptName: nil, imageReference: geometry.image, relationshipType: .selectedFrom)), children: [])
        var nodes: [CADSRNode] = [
            .leaf(AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: CADSRCodes.center, graphicType: .point,
                graphicData: [geometry.center.0, geometry.center.1], relationshipType: relationship
            )), children: [image])
        ]
        if let outline = geometry.outline {
            nodes.append(.leaf(AnyContentItem(SpatialCoordinatesContentItem(
                conceptName: CADSRCodes.outline, graphicType: outline.0, graphicData: outline.1, relationshipType: relationship
            )), children: [image]))
        }
        return nodes
    }

    /// TID 4000/4100 rows 6-9: CODE Summary of Detections/Analyses with TID 4015/4016 INFERRED FROM it
    static func summary(
        concept: CodedConcept,
        status: CADProcessingStatus,
        runs: [CADAlgorithmRun],
        successContainer: CodedConcept,
        failureContainer: CodedConcept,
        runConcept: CodedConcept,
        fallbackAlgorithm: CADAlgorithmIdentification?
    ) -> CADSRNode {
        var children: [CADSRNode] = []
        if status != .notAttempted {
            let succeeded = runs.filter(\.succeeded)
            let failed = runs.filter { !$0.succeeded }
            // TID 4015/4016 row 1: Successful container only for Succeeded / Partially Succeeded
            if (status == .succeeded || status == .partiallySucceeded), !succeeded.isEmpty {
                children.append(.container(conceptName: successContainer, relationship: .inferredFrom,
                                           children: succeeded.map { algorithmRun($0, concept: runConcept, fallbackAlgorithm: fallbackAlgorithm) }))
            }
            // TID 4015/4016 row 3: Failed container only for Failed / Partially Succeeded
            if (status == .failed || status == .partiallySucceeded), !failed.isEmpty {
                children.append(.container(conceptName: failureContainer, relationship: .inferredFrom,
                                           children: failed.map { algorithmRun($0, concept: runConcept, fallbackAlgorithm: fallbackAlgorithm) }))
            }
        }
        return .leaf(AnyContentItem(CodeContentItem(conceptName: concept, conceptCode: status.concept, relationshipType: .contains)), children: children)
    }

    /// TID 4017 / TID 4018: CODE Detection/Analysis Performed with TID 4019, IMAGE and UIDREF rows
    static func algorithmRun(_ run: CADAlgorithmRun, concept: CodedConcept, fallbackAlgorithm: CADAlgorithmIdentification?) -> CADSRNode {
        var children: [CADSRNode] = []
        // Row 2: HAS PROPERTIES INCLUDE TID 4019 (M)
        if let algorithm = run.algorithm ?? fallbackAlgorithm {
            children.append(contentsOf: algorithmIdentification(algorithm, relationship: .hasProperties))
        }
        // Row 3: HAS PROPERTIES IMAGE
        for image in run.images {
            children.append(.leaf(AnyContentItem(ImageContentItem(conceptName: nil, imageReference: image, relationshipType: .hasProperties)), children: []))
        }
        // Row 5: HAS PROPERTIES UIDREF Series Instance UID
        for uid in run.seriesInstanceUIDs {
            children.append(.leaf(AnyContentItem(UIDRefContentItem(conceptName: CADSRCodes.seriesInstanceUID, uidValue: uid, relationshipType: .hasProperties)), children: []))
        }
        return .leaf(AnyContentItem(CodeContentItem(conceptName: concept, conceptCode: run.code, relationshipType: .contains)), children: children)
    }
}
