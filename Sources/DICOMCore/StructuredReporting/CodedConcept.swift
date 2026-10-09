/// DICOM Coded Concept
///
/// Represents a coded concept as used in DICOM Structured Reporting.
/// A coded concept consists of a Code Value, Coding Scheme Designator, and Code Meaning.
///
/// Reference: PS3.3 Section 8.8 - Coded Entry Data
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the triplet, the 16/16/64-character limits (Code Value SH, Coding Scheme Designator SH, Code Meaning LO), Coding Scheme Version, Long Code Value (0008,0119) and URN Code Value (0008,0120) match PS3.3 2026a Table 8.8-1a; the designators in `CodingSchemeDesignator` match PS3.16 2026a Table 8-1 except "HL7" (not registered) and "99PVT" (a private scheme by convention). `ICD10CM` carried "I10", which is WHO ICD-10; it is now "I10C" and `ICD10` was added.

/// Common coding scheme designators used in DICOM
public enum CodingSchemeDesignator: String, Sendable, Equatable, Hashable, CaseIterable {
    /// DICOM Controlled Terminology
    case DCM = "DCM"
    /// SNOMED Clinical Terms (SNOMED-CT)
    case SCT = "SCT"
    /// SNOMED-RT (deprecated, use SCT)
    case SRT = "SRT"
    /// Logical Observation Identifiers Names and Codes
    case LOINC = "LN"
    /// Foundational Model of Anatomy
    case FMA = "FMA"
    /// RadLex - Radiology Lexicon
    case RADLEX = "RADLEX"
    /// Unified Code for Units of Measure
    case UCUM = "UCUM"
    /// ICD-10 (WHO). PS3.16 Table 8-1: I10.
    case ICD10 = "I10"
    /// ICD-10 Clinical Modification. PS3.16 Table 8-1: I10C (was wrongly "I10" until 2026-09-25).
    case ICD10CM = "I10C"
    /// ICD-10 Procedure Coding System
    case ICD10PCS = "I10P"
    /// HL7v2 Tables
    case HL7 = "HL7"
    /// ACR Index for Radiological Diagnoses (deprecated)
    case ACR = "ACR"
    /// NCIt - NCI Thesaurus
    case NCIt = "NCIt"
    /// UMLS - Unified Medical Language System
    case UMLS = "UMLS"
    /// 99-prefixed private coding scheme
    case privateScheme = "99PVT"
    
    /// Returns the display name of the coding scheme
    public var displayName: String {
        switch self {
        case .DCM: return "DICOM Controlled Terminology"
        case .SCT: return "SNOMED Clinical Terms"
        case .SRT: return "SNOMED-RT (legacy)"
        case .LOINC: return "LOINC"
        case .FMA: return "Foundational Model of Anatomy"
        case .RADLEX: return "RadLex"
        case .UCUM: return "UCUM"
        case .ICD10: return "ICD-10"
        case .ICD10CM: return "ICD-10-CM"
        case .ICD10PCS: return "ICD-10-PCS"
        case .HL7: return "HL7v2"
        case .ACR: return "ACR Index"
        case .NCIt: return "NCI Thesaurus"
        case .UMLS: return "UMLS"
        case .privateScheme: return "Private Coding Scheme"
        }
    }
}

/// A coded concept as defined in DICOM
///
/// Coded concepts are the fundamental building blocks of semantic meaning in DICOM.
/// They consist of a triplet: Code Value + Coding Scheme Designator + Code Meaning.
///
/// Example:
/// ```swift
/// let findingType = CodedConcept(
///     codeValue: "121071",
///     codingSchemeDesignator: "DCM",
///     codeMeaning: "Finding"
/// )
/// ```
public struct CodedConcept: Sendable, Equatable, Hashable {
    /// The code value (0008,0100) - unique identifier within the coding scheme
    public let codeValue: String
    
    /// The coding scheme designator (0008,0102) - identifies the coding scheme
    public let codingSchemeDesignator: String
    
    /// The code meaning (0008,0104) - human-readable description
    public let codeMeaning: String
    
    /// Optional coding scheme version (0008,0103)
    public let codingSchemeVersion: String?
    
    /// Optional long code value (0008,0119) - for codes > 16 characters
    public let longCodeValue: String?
    
    /// Optional URN code value (0008,0120) - URN/URL format code
    public let urnCodeValue: String?
    
    /// Creates a coded concept with the standard triplet
    /// - Parameters:
    ///   - codeValue: The code value (max 16 characters for standard, use longCodeValue for longer)
    ///   - codingSchemeDesignator: The coding scheme designator (max 16 characters)
    ///   - codeMeaning: The human-readable meaning (max 64 characters)
    ///   - codingSchemeVersion: Optional version of the coding scheme
    ///   - longCodeValue: Optional long code value for codes > 16 characters
    ///   - urnCodeValue: Optional URN/URL format code value
    public init(
        codeValue: String,
        codingSchemeDesignator: String,
        codeMeaning: String,
        codingSchemeVersion: String? = nil,
        longCodeValue: String? = nil,
        urnCodeValue: String? = nil
    ) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = codingSchemeDesignator
        self.codeMeaning = codeMeaning
        self.codingSchemeVersion = codingSchemeVersion
        self.longCodeValue = longCodeValue
        self.urnCodeValue = urnCodeValue
    }
    
    /// Creates a coded concept using a known coding scheme designator
    /// - Parameters:
    ///   - codeValue: The code value
    ///   - scheme: The coding scheme
    ///   - codeMeaning: The human-readable meaning
    ///   - codingSchemeVersion: Optional version of the coding scheme
    public init(
        codeValue: String,
        scheme: CodingSchemeDesignator,
        codeMeaning: String,
        codingSchemeVersion: String? = nil
    ) {
        self.codeValue = codeValue
        self.codingSchemeDesignator = scheme.rawValue
        self.codeMeaning = codeMeaning
        self.codingSchemeVersion = codingSchemeVersion
        self.longCodeValue = nil
        self.urnCodeValue = nil
    }
    
    /// Returns whether this concept uses DICOM controlled terminology
    public var isDICOMControlled: Bool {
        codingSchemeDesignator == CodingSchemeDesignator.DCM.rawValue
    }
    
    /// Returns whether this concept uses SNOMED
    public var isSNOMED: Bool {
        codingSchemeDesignator == CodingSchemeDesignator.SCT.rawValue ||
        codingSchemeDesignator == CodingSchemeDesignator.SRT.rawValue
    }
    
    /// Returns whether this concept uses a private coding scheme
    public var isPrivate: Bool {
        codingSchemeDesignator.hasPrefix("99")
    }
    
    /// The effective code value, considering long code value
    public var effectiveCodeValue: String {
        longCodeValue ?? urnCodeValue ?? codeValue
    }
}

// MARK: - CustomStringConvertible

extension CodedConcept: CustomStringConvertible {
    public var description: String {
        "(\(codeValue), \(codingSchemeDesignator), \"\(codeMeaning)\")"
    }
}

// MARK: - Validation

extension CodedConcept {
    /// Validation errors for coded concepts
    public enum ValidationError: Error, Sendable, Equatable {
        /// Code value is empty
        case emptyCodeValue
        /// Coding scheme designator is empty
        case emptyCodingSchemeDesignator
        /// Code meaning is empty
        case emptyCodeMeaning
        /// Code value exceeds maximum length (16 characters) without long code value
        case codeValueTooLong(length: Int)
        /// Coding scheme designator exceeds maximum length (16 characters)
        case codingSchemeDesignatorTooLong(length: Int)
        /// Code meaning exceeds maximum length (64 characters)
        case codeMeaningTooLong(length: Int)
    }
    
    /// Validates the coded concept
    /// - Returns: An array of validation errors, empty if valid
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        if codeValue.isEmpty && longCodeValue == nil && urnCodeValue == nil {
            errors.append(.emptyCodeValue)
        }
        
        if codingSchemeDesignator.isEmpty {
            errors.append(.emptyCodingSchemeDesignator)
        }
        
        if codeMeaning.isEmpty {
            errors.append(.emptyCodeMeaning)
        }
        
        // Check length constraints per DICOM standard
        if codeValue.count > 16 && longCodeValue == nil && urnCodeValue == nil {
            errors.append(.codeValueTooLong(length: codeValue.count))
        }
        
        if codingSchemeDesignator.count > 16 {
            errors.append(.codingSchemeDesignatorTooLong(length: codingSchemeDesignator.count))
        }
        
        if codeMeaning.count > 64 {
            errors.append(.codeMeaningTooLong(length: codeMeaning.count))
        }
        
        return errors
    }
    
    /// Returns whether the coded concept is valid
    public var isValid: Bool {
        validate().isEmpty
    }
}

// MARK: - Common DICOM Coded Concepts

extension CodedConcept {
    // MARK: - SR Document Types
    
    /// Language of Content Item and Descendants
    public static let languageOfContentItemAndDescendants = CodedConcept(
        codeValue: "121049",
        scheme: .DCM,
        codeMeaning: "Language of Content Item and Descendants"
    )
    
    /// Country of Language
    public static let countryOfLanguage = CodedConcept(
        codeValue: "121046",
        scheme: .DCM,
        codeMeaning: "Country of Language"
    )
    
    // MARK: - Content Item Concepts
    
    /// Finding
    public static let finding = CodedConcept(
        codeValue: "121071",
        scheme: .DCM,
        codeMeaning: "Finding"
    )
    
    /// Measurement
    public static let measurement = CodedConcept(
        codeValue: "125007",
        scheme: .DCM,
        codeMeaning: "Measurement"
    )
    
    /// Procedure Reported
    public static let procedureReported = CodedConcept(
        codeValue: "121058",
        scheme: .DCM,
        codeMeaning: "Procedure Reported"
    )
    
    /// Observer Type
    public static let observerType = CodedConcept(
        codeValue: "121005",
        scheme: .DCM,
        codeMeaning: "Observer Type"
    )
    
    /// Person Observer Name
    public static let personObserverName = CodedConcept(
        codeValue: "121008",
        scheme: .DCM,
        codeMeaning: "Person Observer Name"
    )
    
    /// Person
    public static let person = CodedConcept(
        codeValue: "121006",
        scheme: .DCM,
        codeMeaning: "Person"
    )
    
    /// Device
    public static let device = CodedConcept(
        codeValue: "121007",
        scheme: .DCM,
        codeMeaning: "Device"
    )
    
    /// Image Reference
    public static let imageReference = CodedConcept(
        codeValue: "121191",
        scheme: .DCM,
        codeMeaning: "Image Reference"
    )
    
    /// Source of Measurement
    public static let sourceOfMeasurement = CodedConcept(
        codeValue: "121112",
        scheme: .DCM,
        codeMeaning: "Source of Measurement"
    )
    
    /// Derivation
    public static let derivation = CodedConcept(
        codeValue: "121401",
        scheme: .DCM,
        codeMeaning: "Derivation"
    )
    
    // MARK: - Units (UCUM)
    
    /// Millimeter unit
    public static let unitMillimeter = CodedConcept(
        codeValue: "mm",
        scheme: .UCUM,
        codeMeaning: "millimeter"
    )
    
    /// Centimeter unit
    public static let unitCentimeter = CodedConcept(
        codeValue: "cm",
        scheme: .UCUM,
        codeMeaning: "centimeter"
    )
    
    /// Square millimeter unit
    public static let unitSquareMillimeter = CodedConcept(
        codeValue: "mm2",
        scheme: .UCUM,
        codeMeaning: "square millimeter"
    )
    
    /// Square centimeter unit
    public static let unitSquareCentimeter = CodedConcept(
        codeValue: "cm2",
        scheme: .UCUM,
        codeMeaning: "square centimeter"
    )
    
    /// Cubic millimeter unit
    public static let unitCubicMillimeter = CodedConcept(
        codeValue: "mm3",
        scheme: .UCUM,
        codeMeaning: "cubic millimeter"
    )
    
    /// Cubic centimeter unit
    public static let unitCubicCentimeter = CodedConcept(
        codeValue: "cm3",
        scheme: .UCUM,
        codeMeaning: "cubic centimeter"
    )
    
    /// Hounsfield unit
    public static let unitHounsfieldUnit = CodedConcept(
        codeValue: "[hnsf'U]",
        scheme: .UCUM,
        codeMeaning: "Hounsfield unit"
    )
    
    /// No units (ratio/count)
    public static let unitNoUnits = CodedConcept(
        codeValue: "1",
        scheme: .UCUM,
        codeMeaning: "no units"
    )
    
    /// Percent
    public static let unitPercent = CodedConcept(
        codeValue: "%",
        scheme: .UCUM,
        codeMeaning: "percent"
    )
    
    /// Degree (angle)
    public static let unitDegree = CodedConcept(
        codeValue: "deg",
        scheme: .UCUM,
        codeMeaning: "degree"
    )
}
