/// DICOM Structured Reporting Template Infrastructure
///
/// Provides foundational types for defining and validating DICOM SR Templates (TID).
/// Templates define the structure and constraints for SR content.
///
/// Reference: PS3.16 Annex A - SR Templates
/// Reference: PS3.16 Chapter 6 - Form of Template Specifications
///
/// NEMA-verified: 2026a, checked 2026-09-25 — `RequirementLevel` is text-diffed against
/// PS3.16 2026a §6.1.7 (M, MC, U, UC), and every `TemplateIdentifier` constant against the
/// TID section titles of PS3.16 2026a Annex A. The template rows themselves live in
/// SRCoreTemplates and SRMeasurementTemplates, generated from the 2026a TID tables by
/// Scripts/generate_sr_templates.py (P10). `TemplateRow` models every column of a
/// PS3.16 §6.1 template table: NL, Rel with Parent (including by-reference "R-"
/// relationships), VT or INCLUDE with its parameter bindings (§6.1.3, §6.2), Concept
/// Name, VM, Req Type, Condition and Value Set Constraint.
///
/// NEMA-verified: 2026a, checked 2026-09-30 — the TID 1401, 1402, 4000-4018, 4020-4023 and
/// 4100-4107 constants are text-diffed against the PS3.16 2026a TID section titles, and their
/// rows (SRMeasurementTemplates, SRCADTemplates) generated from the 2026a TID tables (D50).

import Foundation

// MARK: - Template Identifier

/// Identifier for a DICOM SR Template
///
/// Templates are identified by a Template ID (TID) and an optional version.
/// Example: TID 300 - Measurement, TID 1500 - Measurement Report
public struct TemplateIdentifier: Sendable, Equatable, Hashable {
    /// The numeric template identifier (e.g., 300, 1500)
    public let templateID: String
    
    /// Optional version string for the template
    public let version: String?
    
    /// The mapping resource that defines this template (e.g., "DCMR" for DICOM Content Mapping Resource)
    public let mappingResource: String
    
    /// Creates a template identifier
    /// - Parameters:
    ///   - templateID: The numeric template ID (e.g., "300", "1500")
    ///   - version: Optional version string
    ///   - mappingResource: The mapping resource (default: "DCMR")
    public init(templateID: String, version: String? = nil, mappingResource: String = "DCMR") {
        self.templateID = templateID
        self.version = version
        self.mappingResource = mappingResource
    }
    
    /// Creates a template identifier from an integer TID
    /// - Parameters:
    ///   - tid: The numeric template ID
    ///   - version: Optional version string
    ///   - mappingResource: The mapping resource (default: "DCMR")
    public init(tid: Int, version: String? = nil, mappingResource: String = "DCMR") {
        self.templateID = String(tid)
        self.version = version
        self.mappingResource = mappingResource
    }
}

extension TemplateIdentifier: CustomStringConvertible {
    public var description: String {
        if let version = version {
            return "TID \(templateID) v\(version)"
        }
        return "TID \(templateID)"
    }
}

// MARK: - Well-Known Template Identifiers

extension TemplateIdentifier {
    // MARK: Core Templates
    
    /// TID 300 - Measurement
    public static let measurement = TemplateIdentifier(tid: 300)
    
    /// TID 320 - Image or Spatial Coordinates
    public static let imageOrSpatialCoordinates = TemplateIdentifier(tid: 320)

    /// TID 1601 - Image Library Entry
    ///
    /// Before 2026-09-25 this constant was TID 320, which is "Image or Spatial
    /// Coordinates" in PS3.16; Image Library Entry is TID 1601.
    public static let imageLibraryEntry = TemplateIdentifier(tid: 1601)
    
    /// TID 1001 - Observation Context
    public static let observationContext = TemplateIdentifier(tid: 1001)
    
    /// TID 1002 - Observer Context
    public static let observerContext = TemplateIdentifier(tid: 1002)
    
    /// TID 1204 - Language of Content Item and Descendants
    public static let languageOfContent = TemplateIdentifier(tid: 1204)

    /// TID 301 - Measurement Content
    public static let measurementContent = TemplateIdentifier(tid: 301)

    /// TID 310 - Measurement Properties
    public static let measurementProperties = TemplateIdentifier(tid: 310)

    /// TID 311 - Measurement Statistical Properties
    public static let measurementStatisticalProperties = TemplateIdentifier(tid: 311)

    /// TID 312 - Normal Range Properties
    public static let normalRangeProperties = TemplateIdentifier(tid: 312)

    /// TID 315 - Equation or Table
    public static let equationOrTable = TemplateIdentifier(tid: 315)

    /// TID 321 - Waveform or Temporal Coordinates
    public static let waveformOrTemporalCoordinates = TemplateIdentifier(tid: 321)

    /// TID 1000 - Quotation
    public static let quotation = TemplateIdentifier(tid: 1000)

    /// TID 1003 - Person Observer Identifying Attributes
    public static let personObserverIdentifyingAttributes = TemplateIdentifier(tid: 1003)

    /// TID 1004 - Device Observer Identifying Attributes
    public static let deviceObserverIdentifyingAttributes = TemplateIdentifier(tid: 1004)

    /// TID 1005 - Procedure Study Context
    public static let procedureStudyContext = TemplateIdentifier(tid: 1005)

    /// TID 1006 - Subject Context
    public static let subjectContext = TemplateIdentifier(tid: 1006)

    /// TID 1007 - Subject Context, Patient
    public static let subjectContextPatient = TemplateIdentifier(tid: 1007)

    /// TID 1008 - Subject Context, Fetus
    public static let subjectContextFetus = TemplateIdentifier(tid: 1008)

    /// TID 1009 - Subject Context, Specimen
    public static let subjectContextSpecimen = TemplateIdentifier(tid: 1009)

    /// TID 1010 - Subject Context, Device
    public static let subjectContextDevice = TemplateIdentifier(tid: 1010)

    /// TID 1015 - Person Observer Description
    public static let personObserverDescription = TemplateIdentifier(tid: 1015)

    /// TID 4108 - Tracking Identifier
    public static let trackingIdentifier = TemplateIdentifier(tid: 4108)
    
    // MARK: Measurement Templates
    
    /// TID 1400 - Linear Measurement
    public static let linearMeasurements = TemplateIdentifier(tid: 1400)

    /// TID 1401 - Area Measurement
    public static let areaMeasurement = TemplateIdentifier(tid: 1401)

    /// TID 1402 - Volume Measurement
    public static let volumeMeasurement = TemplateIdentifier(tid: 1402)

    /// TID 1410 - Planar ROI Measurements and Qualitative Evaluations
    public static let planarROIMeasurements = TemplateIdentifier(tid: 1410)

    /// TID 1411 - Volumetric ROI Measurements and Qualitative Evaluations
    public static let volumetricROIMeasurements = TemplateIdentifier(tid: 1411)

    /// TID 1419 - ROI Measurements
    public static let roiMeasurements = TemplateIdentifier(tid: 1419)

    /// TID 1420 - Measurements Derived From Multiple ROI Measurements
    public static let multipleROIMeasurements = TemplateIdentifier(tid: 1420)

    // MARK: Document Templates

    /// TID 1500 - Measurement Report
    public static let measurementReport = TemplateIdentifier(tid: 1500)

    /// TID 1501 - Measurement and Qualitative Evaluation Group
    public static let measurementGroup = TemplateIdentifier(tid: 1501)

    /// TID 1600 - Image Library
    public static let imageLibrary = TemplateIdentifier(tid: 1600)

    /// TID 1502 - Time Point Context
    public static let timePointContext = TemplateIdentifier(tid: 1502)

    /// TID 1602 - Image Library Entry Descriptors
    public static let imageLibraryEntryDescriptors = TemplateIdentifier(tid: 1602)

    /// TID 1603 - Image Library Entry Descriptors for Projection Radiography
    public static let imageLibraryEntryDescriptorsForProjectionRadiography = TemplateIdentifier(tid: 1603)

    /// TID 1604 - Image Library Entry Descriptors for Cross-Sectional Modalities
    public static let imageLibraryEntryDescriptorsForCrossSectionalModalities = TemplateIdentifier(tid: 1604)

    /// TID 1605 - Image Library Entry Descriptors for CT
    public static let imageLibraryEntryDescriptorsForCT = TemplateIdentifier(tid: 1605)

    /// TID 1606 - Image Library Entry Descriptors for MR
    public static let imageLibraryEntryDescriptorsForMR = TemplateIdentifier(tid: 1606)

    /// TID 1607 - Image Library Entry Descriptors for PET
    public static let imageLibraryEntryDescriptorsForPET = TemplateIdentifier(tid: 1607)

    /// TID 1608 - Image Library Entry Descriptors for Prostate Multiparametric MR
    public static let imageLibraryEntryDescriptorsForProstateMultiparametricMR = TemplateIdentifier(tid: 1608)

    // MARK: CAD Templates

    /// TID 4000 - Mammography CAD Document Root
    public static let mammographyCADDocumentRoot = TemplateIdentifier(tid: 4000)

    /// TID 4019 - Algorithm Identification
    public static let algorithmIdentification = TemplateIdentifier(tid: 4019)

    /// TID 4001 - Mammography CAD Overall Impression/Recommendation
    public static let mammographyCADOverallImpressionRecommendation = TemplateIdentifier(tid: 4001)

    /// TID 4002 - Mammography CAD Impression/Recommendation Body
    public static let mammographyCADImpressionRecommendationBody = TemplateIdentifier(tid: 4002)

    /// TID 4003 - Mammography CAD Individual Impression/Recommendation
    public static let mammographyCADIndividualImpressionRecommendation = TemplateIdentifier(tid: 4003)

    /// TID 4004 - Mammography CAD Composite Feature
    public static let mammographyCADCompositeFeature = TemplateIdentifier(tid: 4004)

    /// TID 4005 - Mammography CAD Composite Feature Body
    public static let mammographyCADCompositeFeatureBody = TemplateIdentifier(tid: 4005)

    /// TID 4006 - Mammography CAD Single Image Finding
    public static let mammographyCADSingleImageFinding = TemplateIdentifier(tid: 4006)

    /// TID 4007 - Mammography CAD Breast Composition
    public static let mammographyCADBreastComposition = TemplateIdentifier(tid: 4007)

    /// TID 4008 - Mammography CAD Breast Geometry
    public static let mammographyCADBreastGeometry = TemplateIdentifier(tid: 4008)

    /// TID 4009 - Mammography CAD Individual Calcification
    public static let mammographyCADIndividualCalcification = TemplateIdentifier(tid: 4009)

    /// TID 4010 - Mammography CAD Calcification Cluster
    public static let mammographyCADCalcificationCluster = TemplateIdentifier(tid: 4010)

    /// TID 4011 - Mammography CAD Density
    public static let mammographyCADDensity = TemplateIdentifier(tid: 4011)

    /// TID 4012 - Mammography CAD Non-lesion
    public static let mammographyCADNonLesion = TemplateIdentifier(tid: 4012)

    /// TID 4013 - Mammography CAD Selected Region
    public static let mammographyCADSelectedRegion = TemplateIdentifier(tid: 4013)

    /// TID 4014 - CAD Image Quality
    public static let cadImageQuality = TemplateIdentifier(tid: 4014)

    /// TID 4015 - CAD Detections Performed
    public static let cadDetectionsPerformed = TemplateIdentifier(tid: 4015)

    /// TID 4016 - CAD Analyses Performed
    public static let cadAnalysesPerformed = TemplateIdentifier(tid: 4016)

    /// TID 4017 - CAD Detection Performed
    public static let cadDetectionPerformed = TemplateIdentifier(tid: 4017)

    /// TID 4018 - CAD Analysis Performed
    public static let cadAnalysisPerformed = TemplateIdentifier(tid: 4018)

    /// TID 4020 - CAD Image Library Entry
    public static let cadImageLibraryEntry = TemplateIdentifier(tid: 4020)

    /// TID 4021 - Mammography CAD Geometry
    public static let mammographyCADGeometry = TemplateIdentifier(tid: 4021)

    /// TID 4022 - CAD Observation Context
    public static let cadObservationContext = TemplateIdentifier(tid: 4022)

    /// TID 4023 - CAD Operating Points
    public static let cadOperatingPoints = TemplateIdentifier(tid: 4023)

    /// TID 4100 - Chest CAD Document Root
    public static let chestCADDocumentRoot = TemplateIdentifier(tid: 4100)

    /// TID 4101 - Chest CAD Findings Summary
    public static let chestCADFindingsSummary = TemplateIdentifier(tid: 4101)

    /// TID 4102 - Chest CAD Composite Feature
    public static let chestCADCompositeFeature = TemplateIdentifier(tid: 4102)

    /// TID 4103 - Chest CAD Composite Feature Body
    public static let chestCADCompositeFeatureBody = TemplateIdentifier(tid: 4103)

    /// TID 4104 - Chest CAD Single Image Finding
    public static let chestCADSingleImageFinding = TemplateIdentifier(tid: 4104)

    /// TID 4105 - Chest CAD Descriptors
    public static let chestCADDescriptors = TemplateIdentifier(tid: 4105)

    /// TID 4106 - Response Evaluation
    public static let responseEvaluation = TemplateIdentifier(tid: 4106)

    /// TID 4107 - Chest CAD Geometry
    public static let chestCADGeometry = TemplateIdentifier(tid: 4107)

    @available(*, unavailable, renamed: "mammographyCADDocumentRoot",
               message: "TID 4000 is 'Mammography CAD Document Root' in PS3.16; there is no 'CAD Analysis' template.")
    public static var cadAnalysis: TemplateIdentifier { fatalError() }

    @available(*, unavailable, renamed: "algorithmIdentification",
               message: "TID 4019 is 'Algorithm Identification' in PS3.16; there is no 'CAD Finding' template.")
    public static var cadFinding: TemplateIdentifier { fatalError() }
}

// MARK: - Requirement Level

/// Requirement Type of a template row (PS3.16 §6.1.7)
///
/// The four symbols of PS3.16 2026a §6.1.7: M, MC, U and UC. The requirement type
/// interacts with VM: an M/MC row occurs 1 (VM 1) or 1–n (VM 1-n) times, a U/UC row
/// 0–1 or 0–n times.
///
/// Reference: PS3.16 Section 6.1.7 - Requirement Type
public enum RequirementLevel: String, Sendable, Equatable, Hashable, CaseIterable {
    /// M — Mandatory. Shall be present.
    case mandatory = "M"

    /// MC — Mandatory Conditional. Shall be present if the specified condition is satisfied.
    case mandatoryConditional = "MC"

    /// U — User Option. May or may not be present.
    case userOption = "U"

    /// UC — User Option Conditional. May not be present; may be present according to
    /// the specified condition.
    case userOptionConditional = "UC"

    /// Not a PS3.16 requirement type. Rows that "depend on other factors" are MC or UC.
    @available(*, deprecated, message: "PS3.16 §6.1.7 has no 'C' requirement type; use .mandatoryConditional or .userOptionConditional.")
    case conditional = "C"

    /// The old name for `U`, which is "User Option" in PS3.16, not "User Conditional".
    @available(*, deprecated, renamed: "userOption")
    public static var userConditional: RequirementLevel { .userOption }

    /// The four standard requirement types, in PS3.16 order.
    public static var allCases: [RequirementLevel] {
        [.mandatory, .mandatoryConditional, .userOption, .userOptionConditional]
    }

    /// Display name for the requirement level
    public var displayName: String {
        switch self {
        case .mandatory: return "Mandatory"
        case .mandatoryConditional: return "Mandatory Conditional"
        case .userOption: return "User Option"
        case .userOptionConditional: return "User Option Conditional"
        case .conditional: return "Conditional (non-standard)"
        }
    }

    /// Whether the row shall be present unconditionally (M only; MC depends on its
    /// condition, U and UC are optional).
    public var isMandatory: Bool {
        switch self {
        case .mandatory:
            return true
        case .mandatoryConditional, .userOption, .userOptionConditional, .conditional:
            return false
        }
    }
}

extension RequirementLevel: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

// MARK: - Cardinality

/// Cardinality constraint for template content items
///
/// Defines how many instances of a content item are allowed.
public struct Cardinality: Sendable, Equatable, Hashable {
    /// Minimum number of instances (0 for optional)
    public let minimum: Int
    
    /// Maximum number of instances (nil for unbounded)
    public let maximum: Int?
    
    /// Creates a cardinality constraint
    /// - Parameters:
    ///   - minimum: Minimum instances required
    ///   - maximum: Maximum instances allowed (nil for unbounded)
    public init(minimum: Int, maximum: Int? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }
    
    /// Exactly one instance required (1..1)
    public static let one = Cardinality(minimum: 1, maximum: 1)
    
    /// Zero or one instance allowed (0..1)
    public static let zeroOrOne = Cardinality(minimum: 0, maximum: 1)
    
    /// One or more instances required (1..n)
    public static let oneOrMore = Cardinality(minimum: 1, maximum: nil)
    
    /// Zero or more instances allowed (0..n)
    public static let zeroOrMore = Cardinality(minimum: 0, maximum: nil)
    
    /// Returns whether this cardinality allows zero instances
    public var allowsZero: Bool {
        minimum == 0
    }
    
    /// Returns whether this cardinality allows multiple instances
    public var allowsMultiple: Bool {
        maximum == nil || maximum! > 1
    }
    
    /// Returns whether a given count satisfies this cardinality
    /// - Parameter count: The number of instances
    /// - Returns: True if the count is within the cardinality bounds
    public func isSatisfied(by count: Int) -> Bool {
        if count < minimum {
            return false
        }
        if let max = maximum, count > max {
            return false
        }
        return true
    }
}

extension Cardinality: CustomStringConvertible {
    public var description: String {
        if let max = maximum {
            if minimum == max {
                return "\(minimum)"
            }
            return "\(minimum)..\(max)"
        }
        return "\(minimum)..n"
    }
}

// MARK: - Template Row Condition

/// Condition that determines when a template row applies
///
/// Some template rows are conditional on other content being present.
public enum TemplateRowCondition: Sendable, Equatable {
    /// No condition - row always applies
    case none
    
    /// Row applies if the specified concept is present
    case ifPresent(concept: CodedConcept)
    
    /// Row applies if the specified concept has the specified value
    case ifEquals(concept: CodedConcept, value: CodedConcept)
    
    /// Row applies if the specified concept is not present
    case ifAbsent(concept: CodedConcept)
    
    /// Row applies if any of the conditions are met
    case anyOf([TemplateRowCondition])
    
    /// Row applies if all conditions are met
    case allOf([TemplateRowCondition])
    
    /// Custom condition with description
    case custom(description: String)
}

// MARK: - Template Row

/// Definition of a single row in an SR template
///
/// Each row is one line of a PS3.16 template table (§6.1): either a content item
/// (VT set) or an INCLUDE of another template (`includedTemplate` set, `valueType`
/// nil). Rows nest by `nestingLevel`: a row is a child of the nearest earlier row
/// with a lower level.
///
/// Reference: PS3.16 Section 6.1 - Template Table Field Definition
public struct TemplateRow: Sendable, Equatable {
    /// Unique identifier for this row within the template
    public let rowID: String?
    
    /// Nesting level within the template (0 = top level; one per ">" in the NL column)
    public let nestingLevel: Int
    
    /// Relationship with the parent (PS3.16 §6.1.2).
    ///
    /// nil when the column is empty: the root row of a template, or an INCLUDE whose
    /// included rows carry their own relationships.
    public let relationshipType: RelationshipType?

    /// Whether the relationship is by reference ("R-" prefix, PS3.16 §6.1.2): the
    /// target is a content item elsewhere in the tree, referenced by its position.
    public let isByReference: Bool
    
    /// Value type (PS3.16 §6.1.3); nil for an INCLUDE row.
    public let valueType: ContentItemValueType?
    
    /// Concept name constraint (if specified)
    public let conceptName: ConceptNameConstraint
    
    /// Value constraint (for CODE or NUM items)
    public let valueConstraint: ValueConstraint
    
    /// Requirement level
    public let requirementLevel: RequirementLevel

    /// Value Multiplicity (PS3.16 §6.1.6): how many times the row occurs when it is
    /// present ("1" → 1, "1-n" → 1..n, "2-n" → 2..n).
    public let valueMultiplicity: Cardinality
    
    /// How many times the row may occur, combining VM with the requirement type: the
    /// VM for an M row, and 0 up to the VM's maximum for MC, U and UC rows.
    public let cardinality: Cardinality
    
    /// Condition for when this row applies (the Condition column, as
    /// `.custom(description:)` with the standard's text)
    public let condition: TemplateRowCondition
    
    /// Included template (for rows that reference another template)
    public let includedTemplate: TemplateIdentifier?

    /// Parameter bindings of an INCLUDE row (PS3.16 §6.2), in table order
    public let includeParameters: [TemplateParameterBinding]

    /// The Concept Name cell verbatim, as it appears in PS3.16
    public let conceptNameText: String?

    /// The Value Set Constraint cell verbatim, as it appears in PS3.16
    public let valueSetText: String?

    /// Whether this row includes another template
    public var isInclude: Bool {
        includedTemplate != nil
    }
    
    /// Creates a template row definition
    ///
    /// `valueMultiplicity` defaults to `cardinality` with a minimum of at least 1.
    public init(
        rowID: String? = nil,
        nestingLevel: Int = 0,
        relationshipType: RelationshipType?,
        isByReference: Bool = false,
        valueType: ContentItemValueType?,
        conceptName: ConceptNameConstraint = .any,
        valueConstraint: ValueConstraint = .any,
        requirementLevel: RequirementLevel = .mandatory,
        valueMultiplicity: Cardinality? = nil,
        cardinality: Cardinality = .one,
        condition: TemplateRowCondition = .none,
        includedTemplate: TemplateIdentifier? = nil,
        includeParameters: [TemplateParameterBinding] = [],
        conceptNameText: String? = nil,
        valueSetText: String? = nil
    ) {
        self.rowID = rowID
        self.nestingLevel = nestingLevel
        self.relationshipType = relationshipType
        self.isByReference = isByReference
        self.valueType = valueType
        self.conceptName = conceptName
        self.valueConstraint = valueConstraint
        self.requirementLevel = requirementLevel
        self.valueMultiplicity = valueMultiplicity
            ?? Cardinality(minimum: max(cardinality.minimum, 1), maximum: cardinality.maximum)
        self.cardinality = cardinality
        self.condition = condition
        self.includedTemplate = includedTemplate
        self.includeParameters = includeParameters
        self.conceptNameText = conceptNameText
        self.valueSetText = valueSetText
    }
}

// MARK: - Template Parameters

/// A parameter a template declares (PS3.16 §6.2), such as `$Measurement` in TID 300
public struct TemplateParameter: Sendable, Equatable, Hashable {
    /// Name without the leading "$"
    public let name: String

    /// The Parameter Usage text of the template's Parameters table
    public let usage: String

    public init(name: String, usage: String) {
        self.name = name
        self.usage = usage
    }
}

/// The value an INCLUDE row passes for one parameter of the included template
public struct TemplateParameterBinding: Sendable, Equatable, Hashable {
    /// Parameter name without the leading "$"
    public let name: String

    /// The parsed value
    public let value: TemplateParameterValue

    /// The value text verbatim, as it appears in PS3.16
    public let text: String

    public init(name: String, value: TemplateParameterValue, text: String) {
        self.name = name
        self.value = value
        self.text = text
    }
}

/// A parameter value (PS3.16 §6.2)
public enum TemplateParameterValue: Sendable, Equatable, Hashable {
    /// Another parameter of the including template ("$Name"), passed through
    case parameter(String)

    /// An Enumerated Value code ("EV (…)")
    case code(CodedConcept)

    /// A Defined Term code ("DT (…)")
    case definedTerm(CodedConcept)

    /// A Defined Context Group ("DCID n")
    case contextGroup(Int)

    /// A Baseline Context Group ("BCID n")
    case baselineContextGroup(Int)

    /// Any other value, as text
    case text(String)
}

// MARK: - Concept Name Constraint

/// Constraint on the concept name of a content item
public enum ConceptNameConstraint: Sendable, Equatable {
    /// Any concept name is allowed
    case any
    
    /// Must be exactly this concept
    case exact(CodedConcept)
    
    /// Must be from this context group
    case fromContextGroup(contextGroupID: Int)
    
    /// Must be one of these concepts
    case oneOf([CodedConcept])
    
    /// Must match the baseline concept from CID
    case baselineCID(contextGroupID: Int, baseline: CodedConcept)

    /// Defined Term ("DT (…)", PS3.16 §6.1.4): this code, or another with the same meaning
    case definedTerm(CodedConcept)

    /// From a Baseline Context Group ("BCID n", PS3.16 §6.1.5): other codes may be used
    case fromBaselineContextGroup(contextGroupID: Int)

    /// Supplied by a template parameter ("$Name", PS3.16 §6.2)
    case parameter(String)
}

// MARK: - Value Constraint

/// Constraint on the value of a content item
public enum ValueConstraint: Sendable, Equatable {
    /// Any value is allowed
    case any
    
    /// Must be exactly this coded value
    case exactCode(CodedConcept)
    
    /// Must be from this context group
    case fromContextGroup(contextGroupID: Int)
    
    /// Must be one of these coded values
    case oneOfCodes([CodedConcept])
    
    /// Numeric value must be in specified units
    case numericUnits(unitCode: CodedConcept)
    
    /// Text value with pattern constraint
    case textPattern(String)
    
    /// Custom value constraint with description
    case custom(description: String)

    /// Defined Term code ("DT (…)")
    case definedTermCode(CodedConcept)

    /// From a Baseline Context Group ("BCID n"): other codes may be used
    case fromBaselineContextGroup(contextGroupID: Int)

    /// Supplied by a template parameter ("$Name", PS3.16 §6.2)
    case parameter(String)

    /// Constraint on the Measurement Units of a NUM item ("UNITS = …")
    indirect case units(ValueConstraint)
}

// MARK: - SR Template Protocol

/// Protocol for DICOM SR Template definitions
///
/// Implementations of this protocol define the structure and constraints
/// of specific templates (TIDs).
public protocol SRTemplate: Sendable {
    /// The template identifier (TID)
    static var identifier: TemplateIdentifier { get }
    
    /// Display name for the template
    static var displayName: String { get }
    
    /// Description of what this template is used for
    static var templateDescription: String { get }
    
    /// The rows that define this template's structure
    static var rows: [TemplateRow] { get }
    
    /// Root value type (usually CONTAINER)
    static var rootValueType: ContentItemValueType { get }
    
    /// Whether this template is extensible (allows additional content)
    static var isExtensible: Bool { get }

    /// Whether the order of content items is significant (PS3.16 "Order")
    static var isOrderSignificant: Bool { get }

    /// Whether this is a root template (PS3.16 "Root")
    static var isRoot: Bool { get }

    /// The parameters this template declares (PS3.16 §6.2)
    static var parameters: [TemplateParameter] { get }
}

// MARK: - Template Protocol Default Implementations

extension SRTemplate {
    /// Default root value type is CONTAINER
    public static var rootValueType: ContentItemValueType {
        .container
    }
    
    /// Default to non-extensible
    public static var isExtensible: Bool {
        false
    }

    /// Default to significant order
    public static var isOrderSignificant: Bool {
        true
    }

    /// Default to a non-root template
    public static var isRoot: Bool {
        false
    }

    /// Default to no parameters
    public static var parameters: [TemplateParameter] {
        []
    }
}

// MARK: - Template Registry

/// Thread-safe storage for template types
private final class TemplateStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var templates: [String: any SRTemplate.Type] = [:]
    
    func register(_ templateType: any SRTemplate.Type) {
        lock.lock()
        defer { lock.unlock() }
        templates[templateType.identifier.templateID] = templateType
    }
    
    func template(for templateID: String) -> (any SRTemplate.Type)? {
        lock.lock()
        defer { lock.unlock() }
        return templates[templateID]
    }
    
    func allTemplates() -> [any SRTemplate.Type] {
        lock.lock()
        defer { lock.unlock() }
        return Array(templates.values)
    }
}

/// Registry of known SR templates
///
/// Provides lookup of template definitions by identifier.
public struct TemplateRegistry: Sendable {
    /// Shared singleton instance
    public static let shared = TemplateRegistry()
    
    /// Thread-safe storage
    private let storage = TemplateStorage()
    
    private init() {
        registerBuiltInTemplates()
    }
    
    /// Registers built-in templates
    private func registerBuiltInTemplates() {
        for template in Self.builtInTemplates {
            storage.register(template)
        }
    }

    /// The 73 templates DICOMCore generates from PS3.16 (see SRCoreTemplates,
    /// SRMeasurementTemplates and SRCADTemplates)
    public static let builtInTemplates: [any SRTemplate.Type] = [
        TID300Measurement.self, TID301MeasurementContent.self,
        TID310MeasurementProperties.self, TID311MeasurementStatisticalProperties.self,
        TID312NormalRangeProperties.self, TID315EquationOrTable.self,
        TID320ImageOrSpatialCoordinates.self, TID321WaveformOrTemporalCoordinates.self,
        TID1000Quotation.self, TID1001ObservationContext.self, TID1002ObserverContext.self,
        TID1003PersonObserverIdentifyingAttributes.self,
        TID1004DeviceObserverIdentifyingAttributes.self, TID1005ProcedureStudyContext.self,
        TID1006SubjectContext.self, TID1007SubjectContextPatient.self,
        TID1008SubjectContextFetus.self, TID1009SubjectContextSpecimen.self,
        TID1010SubjectContextDevice.self, TID1015PersonObserverDescription.self,
        TID1204LanguageOfContent.self,
        TID1400LinearMeasurements.self, TID1401AreaMeasurement.self,
        TID1402VolumeMeasurement.self, TID1410PlanarROIMeasurements.self,
        TID1411VolumetricROIMeasurements.self, TID1419ROIMeasurements.self,
        TID1420MultipleROIMeasurements.self,
        TID1500MeasurementReport.self, TID1501MeasurementGroup.self,
        TID1502TimePointContext.self,
        TID1600ImageLibrary.self, TID1601ImageLibraryEntry.self,
        TID1602ImageLibraryEntryDescriptors.self,
        TID1603ImageLibraryEntryDescriptorsForProjectionRadiography.self,
        TID1604ImageLibraryEntryDescriptorsForCrossSectionalModalities.self,
        TID1605ImageLibraryEntryDescriptorsForCT.self,
        TID1606ImageLibraryEntryDescriptorsForMR.self,
        TID1607ImageLibraryEntryDescriptorsForPET.self,
        TID1608ImageLibraryEntryDescriptorsForProstateMultiparametricMR.self,
        TID4019AlgorithmIdentification.self, TID4108TrackingIdentifier.self,
        // TID 4000 and TID 4100 with the templates they include (D50)
        TID4000MammographyCADDocumentRoot.self,
        TID4001MammographyCADOverallImpressionRecommendation.self,
        TID4002MammographyCADImpressionRecommendationBody.self,
        TID4003MammographyCADIndividualImpressionRecommendation.self,
        TID4004MammographyCADCompositeFeature.self, TID4005MammographyCADCompositeFeatureBody.self,
        TID4006MammographyCADSingleImageFinding.self, TID4007MammographyCADBreastComposition.self,
        TID4008MammographyCADBreastGeometry.self, TID4009MammographyCADIndividualCalcification.self,
        TID4010MammographyCADCalcificationCluster.self, TID4011MammographyCADDensity.self,
        TID4012MammographyCADNonLesion.self, TID4013MammographyCADSelectedRegion.self,
        TID4014CADImageQuality.self, TID4015CADDetectionsPerformed.self,
        TID4016CADAnalysesPerformed.self, TID4017CADDetectionPerformed.self,
        TID4018CADAnalysisPerformed.self, TID4020CADImageLibraryEntry.self,
        TID4021MammographyCADGeometry.self, TID4022CADObservationContext.self,
        TID4023CADOperatingPoints.self, TID4100ChestCADDocumentRoot.self,
        TID4101ChestCADFindingsSummary.self, TID4102ChestCADCompositeFeature.self,
        TID4103ChestCADCompositeFeatureBody.self, TID4104ChestCADSingleImageFinding.self,
        TID4105ChestCADDescriptors.self, TID4106ResponseEvaluation.self,
        TID4107ChestCADGeometry.self,
    ]
    
    /// Registers a template type
    /// - Parameter templateType: The template type to register
    public func register<T: SRTemplate>(_ templateType: T.Type) {
        storage.register(templateType)
    }
    
    /// Looks up a template by identifier
    /// - Parameter identifier: The template identifier
    /// - Returns: The template type if found
    public func template(for identifier: TemplateIdentifier) -> (any SRTemplate.Type)? {
        storage.template(for: identifier.templateID)
    }
    
    /// Looks up a template by TID number
    /// - Parameter tid: The template ID number
    /// - Returns: The template type if found
    public func template(tid: Int) -> (any SRTemplate.Type)? {
        template(for: TemplateIdentifier(tid: tid))
    }
    
    /// Returns all registered template identifiers
    public var registeredTemplates: [TemplateIdentifier] {
        storage.allTemplates().map { $0.identifier }
    }
}
