/// CodingScheme - Represents a complete coding scheme with metadata
///
/// Provides a comprehensive representation of a medical coding scheme including
/// its identifier, name, version, and associated metadata.
///
/// Reference: PS3.16 - Content Mapping Resource
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the built-in designators and UIDs are text-diffed against PS3.16 2026a Table 8-1 (Coding Schemes). Fixed 2026-09-25: `icd10CM` carried designator "I10" (WHO ICD-10) with the ICD-10-CM UID and is now "I10C", with a new `icd10` for I10 / 2.16.840.1.113883.6.3; `acr` gained its UID 2.16.840.1.113883.6.76. "HL7" is not a Table 8-1 designator and is documented as such.

#if canImport(Foundation)
import Foundation
#endif

/// A coding scheme used in DICOM for encoding medical concepts
///
/// Coding schemes provide a standardized way to encode medical concepts, findings,
/// anatomical locations, and other healthcare terminology. This struct represents
/// the full metadata for a coding scheme.
///
/// Example:
/// ```swift
/// let snomed = CodingScheme(
///     designator: "SCT",
///     name: "SNOMED Clinical Terms",
///     uid: "2.16.840.1.113883.6.96",
///     version: "20230901"
/// )
/// ```
public struct CodingScheme: Sendable, Equatable, Hashable {
    /// The coding scheme designator (e.g., "SCT", "DCM", "LN")
    /// This is the value used in Code Sequence tag (0008,0102)
    public let designator: String
    
    /// The full human-readable name of the coding scheme
    public let name: String
    
    /// Optional UID that uniquely identifies the coding scheme
    public let uid: String?
    
    /// Optional version of the coding scheme
    public let version: String?
    
    /// Whether this is an external coding scheme (vs DICOM-defined)
    public let isExternal: Bool
    
    /// Optional URL for the coding scheme's official resource
    public let resourceURL: URL?
    
    /// Creates a new coding scheme
    /// - Parameters:
    ///   - designator: The short designator code (max 16 characters per DICOM)
    ///   - name: The full human-readable name
    ///   - uid: Optional unique identifier
    ///   - version: Optional version string
    ///   - isExternal: Whether this is an external scheme (default: false)
    ///   - resourceURL: Optional URL to the coding scheme's official resource
    public init(
        designator: String,
        name: String,
        uid: String? = nil,
        version: String? = nil,
        isExternal: Bool = false,
        resourceURL: URL? = nil
    ) {
        self.designator = designator
        self.name = name
        self.uid = uid
        self.version = version
        self.isExternal = isExternal
        self.resourceURL = resourceURL
    }
}

// MARK: - CustomStringConvertible

extension CodingScheme: CustomStringConvertible {
    public var description: String {
        var desc = "\(designator) (\(name))"
        if let version = version {
            desc += " v\(version)"
        }
        return desc
    }
}

// MARK: - Validation

extension CodingScheme {
    /// Validation errors for coding schemes
    public enum ValidationError: Error, Sendable, Equatable {
        /// Designator is empty
        case emptyDesignator
        /// Designator exceeds maximum length (16 characters)
        case designatorTooLong(length: Int)
        /// Name is empty
        case emptyName
    }
    
    /// Validates the coding scheme
    /// - Returns: An array of validation errors, empty if valid
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        if designator.isEmpty {
            errors.append(.emptyDesignator)
        } else if designator.count > 16 {
            errors.append(.designatorTooLong(length: designator.count))
        }
        
        if name.isEmpty {
            errors.append(.emptyName)
        }
        
        return errors
    }
    
    /// Returns whether the coding scheme is valid
    public var isValid: Bool {
        validate().isEmpty
    }
}

// MARK: - Well-Known Coding Schemes

extension CodingScheme {
    /// DICOM Controlled Terminology (DCM)
    public static let dicom = CodingScheme(
        designator: "DCM",
        name: "DICOM Controlled Terminology",
        uid: "1.2.840.10008.2.16.4",
        isExternal: false,
        resourceURL: URL(string: "https://dicom.nema.org/medical/dicom/current/output/chtml/part16/part16.html")
    )
    
    /// SNOMED Clinical Terms (SNOMED CT)
    public static let snomedCT = CodingScheme(
        designator: "SCT",
        name: "SNOMED Clinical Terms",
        uid: "2.16.840.1.113883.6.96",
        isExternal: true,
        resourceURL: URL(string: "https://www.snomed.org/")
    )
    
    /// SNOMED-RT (legacy, use SCT instead)
    public static let snomedRT = CodingScheme(
        designator: "SRT",
        name: "SNOMED-RT (legacy)",
        uid: "2.16.840.1.113883.6.96",
        isExternal: true
    )
    
    /// Logical Observation Identifiers Names and Codes (LOINC)
    public static let loinc = CodingScheme(
        designator: "LN",
        name: "Logical Observation Identifiers Names and Codes",
        uid: "2.16.840.1.113883.6.1",
        isExternal: true,
        resourceURL: URL(string: "https://loinc.org/")
    )
    
    /// RadLex - Radiology Lexicon
    public static let radlex = CodingScheme(
        designator: "RADLEX",
        name: "RadLex",
        uid: "2.16.840.1.113883.6.256",
        isExternal: true,
        resourceURL: URL(string: "https://radlex.org/")
    )
    
    /// Unified Code for Units of Measure (UCUM)
    public static let ucum = CodingScheme(
        designator: "UCUM",
        name: "Unified Code for Units of Measure",
        uid: "2.16.840.1.113883.6.8",
        isExternal: true,
        resourceURL: URL(string: "https://ucum.org/")
    )
    
    /// Foundational Model of Anatomy (FMA)
    public static let fma = CodingScheme(
        designator: "FMA",
        name: "Foundational Model of Anatomy",
        uid: "2.16.840.1.113883.6.119",
        isExternal: true,
        resourceURL: URL(string: "https://bioportal.bioontology.org/ontologies/FMA")
    )
    
    /// ICD-10 (WHO). PS3.16 Table 8-1: I10, 2.16.840.1.113883.6.3.
    public static let icd10 = CodingScheme(
        designator: "I10",
        name: "ICD-10",
        uid: "2.16.840.1.113883.6.3",
        isExternal: true
    )
    
    /// ICD-10 Clinical Modification. PS3.16 Table 8-1: I10C, 2.16.840.1.113883.6.90.
    ///
    /// Until 2026-09-25 this constant carried the designator "I10", which is WHO ICD-10,
    /// with the ICD-10-CM UID.
    public static let icd10CM = CodingScheme(
        designator: "I10C",
        name: "ICD-10-CM",
        uid: "2.16.840.1.113883.6.90",
        isExternal: true
    )
    
    /// ICD-10 Procedure Coding System
    public static let icd10PCS = CodingScheme(
        designator: "I10P",
        name: "ICD-10 Procedure Coding System",
        uid: "2.16.840.1.113883.6.4",
        isExternal: true
    )
    
    /// NCI Thesaurus
    public static let nciThesaurus = CodingScheme(
        designator: "NCIt",
        name: "NCI Thesaurus",
        uid: "2.16.840.1.113883.3.26.1.1",
        isExternal: true,
        resourceURL: URL(string: "https://ncithesaurus.nci.nih.gov/")
    )
    
    /// Unified Medical Language System
    public static let umls = CodingScheme(
        designator: "UMLS",
        name: "Unified Medical Language System",
        uid: "2.16.840.1.113883.6.86",
        isExternal: true,
        resourceURL: URL(string: "https://www.nlm.nih.gov/research/umls/")
    )
    
    /// HL7 Version 2 tables.
    ///
    /// "HL7" is not a designator in PS3.16 2026a Table 8-1 or 8-2 (HL7 v2 tables are
    /// referenced as "HL7" plus the table number in some IHE profiles, and HL7 v3 code
    /// systems by their own names in Table 8-2). Kept for callers that need it.
    public static let hl7 = CodingScheme(
        designator: "HL7",
        name: "HL7 Version 2 Tables",
        uid: nil,
        isExternal: true
    )
    
    /// ACR Index for Radiological Diagnoses (PS3.16 Table 8-1: ACR, 2.16.840.1.113883.6.76)
    public static let acr = CodingScheme(
        designator: "ACR",
        name: "ACR Index",
        uid: "2.16.840.1.113883.6.76",
        isExternal: true
    )
}

// MARK: - Coding Scheme Registry

/// Registry of known coding schemes
///
/// Provides lookup and management of coding schemes used in DICOM.
/// The registry is pre-populated with well-known schemes.
///
/// Example:
/// ```swift
/// let registry = CodingSchemeRegistry.shared
/// if let snomed = registry.scheme(forDesignator: "SCT") {
///     print("Found SNOMED: \(snomed.name)")
/// }
/// ```
public final class CodingSchemeRegistry: @unchecked Sendable {
    /// The shared registry instance with well-known schemes pre-registered
    public static let shared = CodingSchemeRegistry()
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Internal storage of coding schemes by designator
    private var schemes: [String: CodingScheme] = [:]
    
    /// Creates an empty registry
    public init() {
        registerWellKnownSchemes()
    }
    
    /// Register well-known coding schemes
    private func registerWellKnownSchemes() {
        let wellKnown: [CodingScheme] = [
            .dicom,
            .snomedCT,
            .snomedRT,
            .loinc,
            .radlex,
            .ucum,
            .fma,
            .icd10,
            .icd10CM,
            .icd10PCS,
            .nciThesaurus,
            .umls,
            .hl7,
            .acr
        ]
        
        for scheme in wellKnown {
            schemes[scheme.designator] = scheme
        }
    }
    
    /// Look up a coding scheme by its designator
    /// - Parameter designator: The coding scheme designator (e.g., "SCT", "DCM")
    /// - Returns: The coding scheme if found, nil otherwise
    public func scheme(forDesignator designator: String) -> CodingScheme? {
        lock.lock()
        defer { lock.unlock() }
        return schemes[designator]
    }
    
    /// Register a new coding scheme
    /// - Parameter scheme: The coding scheme to register
    public func register(_ scheme: CodingScheme) {
        lock.lock()
        defer { lock.unlock() }
        schemes[scheme.designator] = scheme
    }
    
    /// Check if a coding scheme is registered
    /// - Parameter designator: The coding scheme designator
    /// - Returns: true if the scheme is registered
    public func isRegistered(_ designator: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return schemes[designator] != nil
    }
    
    /// Get all registered coding schemes
    /// - Returns: Array of all registered coding schemes
    public var allSchemes: [CodingScheme] {
        lock.lock()
        defer { lock.unlock() }
        return Array(schemes.values)
    }
    
    /// Remove a registered coding scheme
    /// - Parameter designator: The designator of the scheme to remove
    /// - Returns: The removed scheme, or nil if not found
    @discardableResult
    public func unregister(_ designator: String) -> CodingScheme? {
        lock.lock()
        defer { lock.unlock() }
        return schemes.removeValue(forKey: designator)
    }
}

// MARK: - CodingSchemeDesignator Extensions

extension CodingSchemeDesignator {
    /// Get the full CodingScheme for this designator
    public var scheme: CodingScheme? {
        CodingSchemeRegistry.shared.scheme(forDesignator: rawValue)
    }
}
