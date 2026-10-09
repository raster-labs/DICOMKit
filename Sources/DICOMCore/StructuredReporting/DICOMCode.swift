/// DICOMCode - DICOM Controlled Terminology (DCM) codes
///
/// Provides comprehensive support for DICOM Controlled Terminology codes
/// as defined in PS3.16. These codes are used extensively in Structured Reporting.
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: PS3.16 Annex D - DICOM Controlled Terminology Definitions
///
/// NEMA-verified: 2026a, checked 2026-09-25 — every constant text-diffed against PS3.16 2026a
/// Table D-1 (code value and code meaning). Constants whose meaning has no DCM code, or is an
/// SCT/NCIt concept or a relationship type, are marked unavailable with the correct reference.

/// A DICOM Controlled Terminology (DCM) code
///
/// DCM codes are numeric identifiers defined by the DICOM standard for
/// encoding concepts used in structured reporting and other DICOM contexts.
///
/// Example:
/// ```swift
/// let finding = DICOMCode.finding
/// print(finding.concept.description) // "(121071, DCM, "Finding")"
/// ```
public struct DICOMCode: Sendable, Equatable, Hashable {
    /// The coded concept representation
    public let concept: CodedConcept
    
    /// The DCM code value
    public var codeValue: String { concept.codeValue }
    
    /// The code meaning (description)
    public var codeMeaning: String { concept.codeMeaning }
    
    /// Creates a DCM code from a code value and meaning
    /// - Parameters:
    ///   - codeValue: The DCM code value (e.g., "121071")
    ///   - codeMeaning: The code meaning
    public init(codeValue: String, codeMeaning: String) {
        self.concept = CodedConcept(
            codeValue: codeValue,
            scheme: .DCM,
            codeMeaning: codeMeaning
        )
    }
    
    /// Creates a DCM code from an existing CodedConcept
    /// - Parameter concept: A coded concept using DCM designator
    /// - Returns: nil if the concept is not a DCM code
    public init?(concept: CodedConcept) {
        guard concept.isDICOMControlled else { return nil }
        self.concept = concept
    }
}

// MARK: - CustomStringConvertible

extension DICOMCode: CustomStringConvertible {
    public var description: String {
        concept.description
    }
}

// MARK: - SR Document Concepts

extension DICOMCode {
    // MARK: - Document Structure
    
    /// Report (121060)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Report\"; 121060 means \"History\"")
    public static var report: DICOMCode { fatalError() }
    
    /// Finding (121071)
    public static let finding = DICOMCode(codeValue: "121071", codeMeaning: "Finding")

    /// Imaging Measurement Report (126000): a Measurement Report document title (CID 7021)
    public static let imagingMeasurementReport = DICOMCode(codeValue: "126000", codeMeaning: "Imaging Measurement Report")
    
    /// Measurement (125007)
    @available(*, unavailable, message: "125007 does not mean \"Measurement\"; use measurementGroup (125007 is \"Measurement Group\")")
    public static var measurement: DICOMCode { fatalError() }
    
    /// Measurement Group (125007)
    public static let measurementGroup = DICOMCode(codeValue: "125007", codeMeaning: "Measurement Group")
    
    /// Procedure Reported (121058)
    public static let procedureReported = DICOMCode(codeValue: "121058", codeMeaning: "Procedure reported")
    
    /// Imaging Measurements (126010)
    public static let imagingMeasurements = DICOMCode(codeValue: "126010", codeMeaning: "Imaging Measurements")
    
    /// Derived Imaging Measurements (126011)
    public static let derivedImagingMeasurements = DICOMCode(codeValue: "126011", codeMeaning: "Derived Imaging Measurements")
    
    /// Summary (121070)
    public static let summary = DICOMCode(codeValue: "121111", codeMeaning: "Summary")
    
    /// Conclusion (121076)
    public static let conclusion = DICOMCode(codeValue: "121077", codeMeaning: "Conclusion")
    
    /// Impression (121077)
    public static let impression = DICOMCode(codeValue: "121073", codeMeaning: "Impression")
    
    /// Recommendation (121074)
    public static let recommendation = DICOMCode(codeValue: "121075", codeMeaning: "Recommendation")
    
    /// Addendum (121078)
    public static let addendum = DICOMCode(codeValue: "121078", codeMeaning: "Addendum")
    
    /// Request (121062)
    public static let request = DICOMCode(codeValue: "121062", codeMeaning: "Request")
    
    /// Clinical History (121060)
    public static let clinicalHistory = DICOMCode(codeValue: "121060", codeMeaning: "History")
    
    /// Current Procedure Descriptions (121064)
    public static let currentProcedureDescriptions = DICOMCode(codeValue: "121064", codeMeaning: "Current Procedure Descriptions")
    
    /// Comparison Study (121068)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Comparison Study\"; 121068 means \"Previous Findings\"")
    public static var comparisonStudy: DICOMCode { fatalError() }
    
    // MARK: - Observer Context
    
    /// Observer Type (121005)
    public static let observerType = DICOMCode(codeValue: "121005", codeMeaning: "Observer Type")
    
    /// Person Observer Name (121008)
    public static let personObserverName = DICOMCode(codeValue: "121008", codeMeaning: "Person Observer Name")
    
    /// Device Observer UID (121012)
    public static let deviceObserverUID = DICOMCode(codeValue: "121012", codeMeaning: "Device Observer UID")
    
    /// Device Observer Name (121013)
    public static let deviceObserverName = DICOMCode(codeValue: "121013", codeMeaning: "Device Observer Name")
    
    /// Device Observer Manufacturer (121014)
    public static let deviceObserverManufacturer = DICOMCode(codeValue: "121014", codeMeaning: "Device Observer Manufacturer")
    
    /// Device Observer Model Name (121015)
    public static let deviceObserverModelName = DICOMCode(codeValue: "121015", codeMeaning: "Device Observer Model Name")
    
    /// Device Observer Serial Number (121016)
    public static let deviceObserverSerialNumber = DICOMCode(codeValue: "121016", codeMeaning: "Device Observer Serial Number")
    
    /// Person (121006)
    public static let person = DICOMCode(codeValue: "121006", codeMeaning: "Person")
    
    /// Device (121007)
    public static let device = DICOMCode(codeValue: "121007", codeMeaning: "Device")
    
    // MARK: - Subject Context
    
    /// Subject Name (121029)
    public static let subjectName = DICOMCode(codeValue: "121029", codeMeaning: "Subject Name")
    
    /// Subject ID (121030)
    public static let subjectID = DICOMCode(codeValue: "121030", codeMeaning: "Subject ID")
    
    /// Subject Birth Date (121031)
    public static let subjectBirthDate = DICOMCode(codeValue: "121031", codeMeaning: "Subject Birth Date")
    
    /// Subject Sex (121032)
    public static let subjectSex = DICOMCode(codeValue: "121032", codeMeaning: "Subject Sex")
    
    /// Subject Species (121024)
    public static let subjectSpecies = DICOMCode(codeValue: "121034", codeMeaning: "Subject Species")
    
    /// Subject Breed (121025)
    public static let subjectBreed = DICOMCode(codeValue: "121035", codeMeaning: "Subject Breed")
    
    // MARK: - Language Context
    
    /// Language of Content Item and Descendants (121049)
    public static let languageOfContentItemAndDescendants = DICOMCode(codeValue: "121049", codeMeaning: "Language of Content Item and Descendants")
    
    /// Country of Language (121046)
    public static let countryOfLanguage = DICOMCode(codeValue: "121046", codeMeaning: "Country of Language")
}

// MARK: - Measurement Concepts

extension DICOMCode {
    // MARK: - Measurement Types
    
    /// Diameter (131190)
    @available(*, unavailable, message: "\"Diameter\" is not a DCM concept; it is (81827009, SCT, \"Diameter\"). Use CodedConcept(codeValue: \"81827009\", scheme: .SCT, codeMeaning: \"Diameter\")")
    public static var diameter: DICOMCode { fatalError() }
    
    /// Long Axis (103340)
    @available(*, unavailable, message: "\"Long Axis\" is not a DCM concept; it is (103339001, SCT, \"Long Axis\"). Use CodedConcept(codeValue: \"103339001\", scheme: .SCT, codeMeaning: \"Long Axis\")")
    public static var longAxis: DICOMCode { fatalError() }
    
    /// Short Axis (103339)
    @available(*, unavailable, message: "\"Short Axis\" is not a DCM concept; it is (103340004, SCT, \"Short Axis\"). Use CodedConcept(codeValue: \"103340004\", scheme: .SCT, codeMeaning: \"Short Axis\")")
    public static var shortAxis: DICOMCode { fatalError() }
    
    /// Perpendicular Axis (103338)
    @available(*, unavailable, message: "\"Perpendicular Axis\" is not a DCM concept; it is (131189007, SCT, \"Perpendicular Axis\"). Use CodedConcept(codeValue: \"131189007\", scheme: .SCT, codeMeaning: \"Perpendicular Axis\")")
    public static var perpendicularAxis: DICOMCode { fatalError() }
    
    /// Area (131184)
    @available(*, unavailable, message: "\"Area\" is not a DCM concept; it is (42798000, SCT, \"Area\"). Use CodedConcept(codeValue: \"42798000\", scheme: .SCT, codeMeaning: \"Area\")")
    public static var area: DICOMCode { fatalError() }
    
    /// Volume (118565)
    @available(*, unavailable, message: "\"Volume\" is not a DCM concept; it is (118565006, SCT, \"Volume\"). Use CodedConcept(codeValue: \"118565006\", scheme: .SCT, codeMeaning: \"Volume\")")
    public static var volume: DICOMCode { fatalError() }
    
    /// Circumference (131183)
    @available(*, unavailable, message: "\"Circumference\" is not a DCM concept; it is (74551000, SCT, \"Circumference\"). Use CodedConcept(codeValue: \"74551000\", scheme: .SCT, codeMeaning: \"Circumference\")")
    public static var circumference: DICOMCode { fatalError() }
    
    /// Perimeter (131189)
    @available(*, unavailable, message: "\"Perimeter\" is not a DCM concept; it is (131191004, SCT, \"Perimeter\"). Use CodedConcept(codeValue: \"131191004\", scheme: .SCT, codeMeaning: \"Perimeter\")")
    public static var perimeter: DICOMCode { fatalError() }
    
    /// Length (118558)
    @available(*, unavailable, message: "\"Length\" is not a DCM concept; it is (410668003, SCT, \"Length\"). Use CodedConcept(codeValue: \"410668003\", scheme: .SCT, codeMeaning: \"Length\")")
    public static var length: DICOMCode { fatalError() }
    
    /// Width (118559)
    @available(*, unavailable, message: "\"Width\" is not a DCM concept; it is (103355008, SCT, \"Width\"). Use CodedConcept(codeValue: \"103355008\", scheme: .SCT, codeMeaning: \"Width\")")
    public static var width: DICOMCode { fatalError() }
    
    /// Height (121211)
    public static let height = DICOMCode(codeValue: "121207", codeMeaning: "Height")
    
    /// Depth (121212)
    public static let depth = DICOMCode(codeValue: "111020", codeMeaning: "Depth")
    
    // MARK: - Image Measurements
    
    /// Mean Value (121401)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Mean Value\"; 121401 means \"Derivation\"")
    public static var meanValue: DICOMCode { fatalError() }
    
    /// Maximum Value (121403)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Maximum Value\"; 121403 means \"Level of Significance\"")
    public static var maximumValue: DICOMCode { fatalError() }
    
    /// Minimum Value (121402)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Minimum Value\"; 121402 means \"Normality\"")
    public static var minimumValue: DICOMCode { fatalError() }
    
    /// Standard Deviation (121404)
    public static let standardDeviation = DICOMCode(codeValue: "113061", codeMeaning: "Standard Deviation")
    
    /// Median (121405)
    public static let median = DICOMCode(codeValue: "130290", codeMeaning: "Median")
    
    /// Mode (121406)
    @available(*, unavailable, message: "\"Mode\" is not a DCM concept; it is (373100007, SCT, \"Mode\"). Use CodedConcept(codeValue: \"373100007\", scheme: .SCT, codeMeaning: \"Mode\")")
    public static var mode: DICOMCode { fatalError() }
    
    /// Count (121407)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Count\"; 121407 means \"Normal Range description\"")
    public static var count: DICOMCode { fatalError() }
    
    /// Sum (121408)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Sum\"; 121408 means \"Normal Range Authority\"")
    public static var sum: DICOMCode { fatalError() }
    
    /// Attenuation Coefficient (112031)
    public static let attenuationCoefficient = DICOMCode(codeValue: "112031", codeMeaning: "Attenuation Coefficient")
    
    // MARK: - Measurement Properties
    
    /// Source of Measurement (121112)
    public static let sourceOfMeasurement = DICOMCode(codeValue: "121112", codeMeaning: "Source of Measurement")
    
    /// Derivation (121401)
    public static let derivation = DICOMCode(codeValue: "121401", codeMeaning: "Derivation")
    
    /// Derivation Parameter (121413)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Derivation Parameter\", and 121413 is not a DCM code")
    public static var derivationParameter: DICOMCode { fatalError() }
    
    /// Image Region (130488)
    public static let imageRegion = DICOMCode(codeValue: "111030", codeMeaning: "Image Region")
    
    /// Tracking Identifier (112039)
    public static let trackingIdentifier = DICOMCode(codeValue: "112039", codeMeaning: "Tracking Identifier")
    
    /// Tracking Unique Identifier (112040)
    public static let trackingUniqueIdentifier = DICOMCode(codeValue: "112040", codeMeaning: "Tracking Unique Identifier")
}

// MARK: - Reference Concepts

extension DICOMCode {
    /// Image Reference (121191)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Image Reference\"; 121191 means \"Referenced Segment\"")
    public static var imageReference: DICOMCode { fatalError() }
    
    /// Composite Reference (121190)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Composite Reference\"; 121190 means \"Referenced Frames\"")
    public static var compositeReference: DICOMCode { fatalError() }
    
    /// Waveform Reference (121192)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Waveform Reference\"; 121192 means \"Device Subject\"")
    public static var waveformReference: DICOMCode { fatalError() }
    
    /// Source Image for Segmentation (121324)
    public static let sourceImageForSegmentation = DICOMCode(codeValue: "121233", codeMeaning: "Source image for segmentation")
    
    /// Source Series for Segmentation (121232)
    public static let sourceSeriesForSegmentation = DICOMCode(codeValue: "121232", codeMeaning: "Source series for segmentation")
}

// MARK: - Qualitative Evaluation

extension DICOMCode {
    // MARK: - Assessment Types
    
    /// Qualitative Evaluation (C0034375)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Qualitative Evaluation\", and C0034375 is not a DCM code")
    public static var qualitativeEvaluation: DICOMCode { fatalError() }
    
    /// Assessment (121073)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Assessment\"; 121073 means \"Impression\"")
    public static var assessment: DICOMCode { fatalError() }
    
    /// Probability of Cancer (121208)
    public static let probabilityOfCancer = DICOMCode(codeValue: "111047", codeMeaning: "Probability of cancer")
    
    /// Abnormality (121072)
    @available(*, unavailable, message: "\"Abnormality\" is not a DCM concept; it is (C9440, NCIt, \"Abnormality\"). Use CodedConcept(codeValue: \"C9440\", scheme: .NCIt, codeMeaning: \"Abnormality\")")
    public static var abnormality: DICOMCode { fatalError() }
    
    // MARK: - Change Assessment
    
    /// No Change (121056)
    @available(*, unavailable, message: "\"No Change\" is not a DCM concept; it is (260388006, SCT, \"No change\"). Use CodedConcept(codeValue: \"260388006\", scheme: .SCT, codeMeaning: \"No change\")")
    public static var noChange: DICOMCode { fatalError() }
    
    /// Progression (121057)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Progression\"; 121057 means \"Perimeter outline\"")
    public static var progression: DICOMCode { fatalError() }
    
    /// Improvement (121055)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Improvement\"; 121055 means \"Path\"")
    public static var improvement: DICOMCode { fatalError() }
}

// MARK: - Relationship Type Codes

extension DICOMCode {
    /// Contains (121311)
    @available(*, unavailable, message: "\"Contains\" is a relationship, not a code; use RelationshipType.contains")
    public static var contains: DICOMCode { fatalError() }
    
    /// Has Properties (121309)
    @available(*, unavailable, message: "\"Has Properties\" is a relationship, not a code; use RelationshipType.hasProperties")
    public static var hasProperties: DICOMCode { fatalError() }
    
    /// Has Observation Context (121310)
    @available(*, unavailable, message: "\"Has Observation Context\" is a relationship, not a code; use RelationshipType.hasObsContext")
    public static var hasObservationContext: DICOMCode { fatalError() }
    
    /// Has Acquisition Context (121312)
    @available(*, unavailable, message: "\"Has Acquisition Context\" is a relationship, not a code; use RelationshipType.hasAcqContext")
    public static var hasAcquisitionContext: DICOMCode { fatalError() }
    
    /// Inferred From (121307)
    @available(*, unavailable, message: "\"Inferred From\" is a relationship, not a code; use RelationshipType.inferredFrom")
    public static var inferredFrom: DICOMCode { fatalError() }
    
    /// Selected From (121308)
    @available(*, unavailable, message: "\"Selected From\" is a relationship, not a code; use RelationshipType.selectedFrom")
    public static var selectedFrom: DICOMCode { fatalError() }
    
    /// Has Concept Modifier (121313)
    @available(*, unavailable, message: "\"Has Concept Modifier\" is a relationship, not a code; use RelationshipType.hasConceptMod")
    public static var hasConceptModifier: DICOMCode { fatalError() }
}

// MARK: - SR Document Title Codes

extension DICOMCode {
    /// Basic Diagnostic Imaging Report (126000)
    @available(*, unavailable, message: "126000 does not mean \"Basic Diagnostic Imaging Report\"; use imagingMeasurementReport (126000 is \"Imaging Measurement Report\")")
    public static var basicDiagnosticImagingReport: DICOMCode { fatalError() }
    
    /// Comprehensive SR (121181)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Comprehensive SR\"; 121181 means \"DICOM Object Catalog\"")
    public static var comprehensiveSR: DICOMCode { fatalError() }
    
    /// Mammography CAD Report (111001)
    public static let mammographyCADReport = DICOMCode(codeValue: "111036", codeMeaning: "Mammography CAD Report")
    
    /// Chest CAD Report (111002)
    public static let chestCADReport = DICOMCode(codeValue: "112000", codeMeaning: "Chest CAD Report")
    
    /// Colon CAD Report (111003)
    public static let colonCADReport = DICOMCode(codeValue: "112220", codeMeaning: "Colon CAD Report")
    
    /// Procedure Log (121184)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Procedure Log\", and 121184 is not a DCM code")
    public static var procedureLog: DICOMCode { fatalError() }
    
    /// X-Ray Radiation Dose Report (113701)
    public static let xRayRadiationDoseReport = DICOMCode(codeValue: "113701", codeMeaning: "X-Ray Radiation Dose Report")
    
    /// CT Dose Length Product Total (113813)
    public static let ctDoseLengthProductTotal = DICOMCode(codeValue: "113813", codeMeaning: "CT Dose Length Product Total")
    
    /// Measurement Report (126000)
    @available(*, unavailable, message: "126000 does not mean \"Measurement Report\"; use imagingMeasurementReport (126000 is \"Imaging Measurement Report\")")
    public static var measurementReport: DICOMCode { fatalError() }
}

// MARK: - Activity Codes

extension DICOMCode {
    /// Study (110180)
    public static let study = DICOMCode(codeValue: "113014", codeMeaning: "Study")
    
    /// Series (110181)
    public static let series = DICOMCode(codeValue: "113015", codeMeaning: "Series")
    
    /// Instance (110182)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Instance\"; 110182 means \"Node ID\"")
    public static var instance: DICOMCode { fatalError() }
    
    /// Image (121192)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Image\"; 121192 means \"Device Subject\"")
    public static var image: DICOMCode { fatalError() }
    
    /// Composite Object (121193)
    @available(*, unavailable, message: "PS3.16 2026a Annex D has no DCM code meaning \"Composite Object\"; 121193 means \"Device Subject Name\"")
    public static var compositeObject: DICOMCode { fatalError() }
}

// MARK: - CodedConcept Convenience

extension CodedConcept {
    /// Create a CodedConcept from a DICOMCode
    /// - Parameter dicomCode: The DCM code
    /// - Returns: A coded concept with DCM designator
    public init(dicomCode: DICOMCode) {
        self = dicomCode.concept
    }
    
    /// Attempt to convert this coded concept to a DICOMCode
    /// - Returns: A DICOMCode if this is a DCM concept, nil otherwise
    public var asDICOMCode: DICOMCode? {
        DICOMCode(concept: self)
    }
}
