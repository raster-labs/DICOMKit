/// CodeMapper - Cross-terminology mapping utilities
///
/// Provides utilities for mapping codes between different terminologies
/// and looking up equivalent codes across coding schemes.
///
/// Reference: PS3.16 - Content Mapping Resource

#if canImport(Foundation)
import Foundation
#endif

/// A cross-terminology code mapper
///
/// Enables mapping between equivalent codes in different coding schemes.
/// For example, mapping between SNOMED CT and RadLex codes for the same concept.
///
/// Example:
/// ```swift
/// let mapper = CodeMapper.shared
/// if let radlex = mapper.mapCode(SNOMEDCode.liver.concept, to: .RADLEX) {
///     print("RadLex equivalent: \(radlex)")
/// }
/// ```
/// NEMA-verified: 2026a, checked 2026-09-25 — carries a hand-written cross-scheme mapping table; the DCM and SCT concepts in it are checked against PS3.16 2026a (all match). The three SRT laterality codes (G-A100, G-A101, G-A102) are from the retired SNOMED-RT designator and no longer appear in PS3.16; they are kept so legacy objects can be mapped to SCT.
public final class CodeMapper: @unchecked Sendable {
    /// The shared code mapper instance
    public static let shared = CodeMapper()
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Internal storage of mappings
    /// Key: source concept, Value: dictionary of target scheme to target concept
    private var mappings: [CodedConcept: [String: CodedConcept]] = [:]
    
    /// Creates an empty code mapper
    public init() {
        registerWellKnownMappings()
    }
    
    /// Map a coded concept to another coding scheme
    /// - Parameters:
    ///   - concept: The source coded concept
    ///   - targetScheme: The target coding scheme designator
    /// - Returns: The equivalent concept in the target scheme, or nil if no mapping exists
    public func mapCode(_ concept: CodedConcept, to targetScheme: CodingSchemeDesignator) -> CodedConcept? {
        mapCode(concept, toDesignator: targetScheme.rawValue)
    }
    
    /// Map a coded concept to another coding scheme by designator string
    /// - Parameters:
    ///   - concept: The source coded concept
    ///   - targetDesignator: The target coding scheme designator string
    /// - Returns: The equivalent concept in the target scheme, or nil if no mapping exists
    public func mapCode(_ concept: CodedConcept, toDesignator targetDesignator: String) -> CodedConcept? {
        lock.lock()
        defer { lock.unlock() }
        
        // If the concept is already in the target scheme, return it
        if concept.codingSchemeDesignator == targetDesignator {
            return concept
        }
        
        return mappings[concept]?[targetDesignator]
    }
    
    /// Register a bidirectional mapping between two concepts
    /// - Parameters:
    ///   - concept1: The first concept
    ///   - concept2: The second concept
    public func registerMapping(between concept1: CodedConcept, and concept2: CodedConcept) {
        lock.lock()
        defer { lock.unlock() }
        
        // Add mapping from concept1 to concept2
        if mappings[concept1] == nil {
            mappings[concept1] = [:]
        }
        mappings[concept1]?[concept2.codingSchemeDesignator] = concept2
        
        // Add reverse mapping from concept2 to concept1
        if mappings[concept2] == nil {
            mappings[concept2] = [:]
        }
        mappings[concept2]?[concept1.codingSchemeDesignator] = concept1
    }
    
    /// Register a mapping from a source concept to multiple target concepts
    /// - Parameters:
    ///   - source: The source concept
    ///   - targets: The target concepts in different coding schemes
    public func registerMappings(from source: CodedConcept, to targets: [CodedConcept]) {
        for target in targets {
            registerMapping(between: source, and: target)
        }
        
        // Also register mappings between the targets
        for i in 0..<targets.count {
            for j in (i+1)..<targets.count {
                registerMapping(between: targets[i], and: targets[j])
            }
        }
    }
    
    /// Get all known mappings for a concept
    /// - Parameter concept: The source concept
    /// - Returns: Dictionary of coding scheme designator to equivalent concept
    public func allMappings(for concept: CodedConcept) -> [String: CodedConcept] {
        lock.lock()
        defer { lock.unlock() }
        return mappings[concept] ?? [:]
    }
    
    /// Check if a mapping exists between two concepts
    /// - Parameters:
    ///   - concept: The source concept
    ///   - targetScheme: The target coding scheme
    /// - Returns: true if a mapping exists
    public func hasMapping(for concept: CodedConcept, to targetScheme: CodingSchemeDesignator) -> Bool {
        mapCode(concept, to: targetScheme) != nil
    }
    
    /// Get the display name for a concept, preferring a specific coding scheme
    /// - Parameters:
    ///   - concept: The coded concept
    ///   - preferredScheme: The preferred coding scheme for display name
    /// - Returns: The code meaning from the preferred scheme if available, otherwise the original
    public func displayName(for concept: CodedConcept, preferredScheme: CodingSchemeDesignator = .SCT) -> String {
        if let mapped = mapCode(concept, to: preferredScheme) {
            return mapped.codeMeaning
        }
        return concept.codeMeaning
    }
}

// MARK: - Well-Known Mappings

extension CodeMapper {
    /// Register commonly used cross-terminology mappings
    private func registerWellKnownMappings() {
        // Anatomical locations - SNOMED CT to RadLex
        registerAnatomicalMappings()
        
        // Finding types
        registerFindingMappings()
        
        // Laterality
        registerLateralityMappings()
        
        // Imaging modalities
        registerModalityMappings()
    }
    
    private func registerAnatomicalMappings() {
        // Brain
        registerMapping(
            between: SNOMEDCode.brain.concept,
            and: RadLexCode.brain.concept
        )
        
        // Liver
        registerMapping(
            between: SNOMEDCode.liver.concept,
            and: RadLexCode.liver.concept
        )
        
        // Kidney
        registerMapping(
            between: SNOMEDCode.kidney.concept,
            and: RadLexCode.kidney.concept
        )
        
        // Spleen
        registerMapping(
            between: SNOMEDCode.spleen.concept,
            and: RadLexCode.spleen.concept
        )
        
        // Pancreas
        registerMapping(
            between: SNOMEDCode.pancreas.concept,
            and: RadLexCode.pancreas.concept
        )
        
        // Lung
        registerMapping(
            between: SNOMEDCode.lung.concept,
            and: RadLexCode.lung.concept
        )
        
        // Heart
        registerMapping(
            between: SNOMEDCode.heart.concept,
            and: RadLexCode.heart.concept
        )
        
        // Breast
        registerMapping(
            between: SNOMEDCode.breast.concept,
            and: RadLexCode.breast.concept
        )
        
        // Prostate
        registerMapping(
            between: SNOMEDCode.prostate.concept,
            and: RadLexCode.prostate.concept
        )
        
        // Thyroid
        registerMapping(
            between: SNOMEDCode.thyroidGland.concept,
            and: RadLexCode.thyroidGland.concept
        )
        
        // Body regions
        registerMapping(
            between: SNOMEDCode.head.concept,
            and: RadLexCode.head.concept
        )
        
        registerMapping(
            between: SNOMEDCode.neck.concept,
            and: RadLexCode.neck.concept
        )
        
        registerMapping(
            between: SNOMEDCode.chest.concept,
            and: RadLexCode.chest.concept
        )
        
        registerMapping(
            between: SNOMEDCode.abdomen.concept,
            and: RadLexCode.abdomen.concept
        )
        
        registerMapping(
            between: SNOMEDCode.pelvis.concept,
            and: RadLexCode.pelvis.concept
        )
        
        registerMapping(
            between: SNOMEDCode.spine.concept,
            and: RadLexCode.spine.concept
        )
    }
    
    private func registerFindingMappings() {
        // Mass
        registerMapping(
            between: SNOMEDCode.mass.concept,
            and: RadLexCode.mass.concept
        )
        
        // Nodule
        registerMapping(
            between: SNOMEDCode.nodule.concept,
            and: RadLexCode.nodule.concept
        )
        
        // Lesion
        registerMapping(
            between: SNOMEDCode.lesion.concept,
            and: RadLexCode.lesion.concept
        )
        
        // Cyst
        registerMapping(
            between: SNOMEDCode.cyst.concept,
            and: RadLexCode.cyst.concept
        )
        
        // Calcification
        registerMapping(
            between: SNOMEDCode.calcification.concept,
            and: RadLexCode.calcification.concept
        )
        
        // Hemorrhage
        registerMapping(
            between: SNOMEDCode.hemorrhage.concept,
            and: RadLexCode.hemorrhage.concept
        )
        
        // Edema
        registerMapping(
            between: SNOMEDCode.edema.concept,
            and: RadLexCode.edema.concept
        )
        
        // Fracture
        registerMapping(
            between: SNOMEDCode.fracture.concept,
            and: RadLexCode.fracture.concept
        )
        
        // Stenosis
        registerMapping(
            between: SNOMEDCode.stenosis.concept,
            and: RadLexCode.stenosis.concept
        )
        
        // Metastasis
        registerMapping(
            between: SNOMEDCode.metastasis.concept,
            and: RadLexCode.metastasis.concept
        )
    }
    
    private func registerLateralityMappings() {
        // DCM laterality codes mapped to SNOMED
        registerMapping(
            between: CodedConcept(codeValue: "G-A100", scheme: .SRT, codeMeaning: "Right"),
            and: SNOMEDCode.right.concept
        )
        
        registerMapping(
            between: CodedConcept(codeValue: "G-A101", scheme: .SRT, codeMeaning: "Left"),
            and: SNOMEDCode.left.concept
        )
        
        registerMapping(
            between: CodedConcept(codeValue: "G-A102", scheme: .SRT, codeMeaning: "Bilateral"),
            and: SNOMEDCode.bilateral.concept
        )
    }
    
    private func registerModalityMappings() {
        // CT
        registerMapping(
            between: SNOMEDCode.computedTomography.concept,
            and: RadLexCode.computedTomography.concept
        )
        
        // MRI
        registerMapping(
            between: SNOMEDCode.magneticResonanceImaging.concept,
            and: RadLexCode.magneticResonanceImaging.concept
        )
        
        // Radiography
        registerMapping(
            between: SNOMEDCode.radiography.concept,
            and: RadLexCode.radiography.concept
        )
        
        // Ultrasound
        registerMapping(
            between: SNOMEDCode.ultrasonography.concept,
            and: RadLexCode.ultrasound.concept
        )
        
        // PET
        registerMapping(
            between: SNOMEDCode.positronEmissionTomography.concept,
            and: RadLexCode.petImaging.concept
        )
        
        // Mammography
        registerMapping(
            between: SNOMEDCode.mammography.concept,
            and: RadLexCode.mammography.concept
        )
        
        // Fluoroscopy
        registerMapping(
            between: SNOMEDCode.fluoroscopy.concept,
            and: RadLexCode.fluoroscopy.concept
        )
    }
}

// MARK: - Code Equivalence

/// Protocol for types that can be checked for semantic equivalence
public protocol CodeEquivalent {
    /// The coded concept representation
    var concept: CodedConcept { get }
}

extension CodeEquivalent {
    /// Check if this code is semantically equivalent to another
    /// - Parameter other: Another code to compare
    /// - Returns: true if the codes are semantically equivalent
    public func isEquivalent(to other: any CodeEquivalent) -> Bool {
        let mapper = CodeMapper.shared
        
        // Same concept
        if concept == other.concept {
            return true
        }
        
        // Check if there's a mapping between them
        if let mapped = mapper.mapCode(concept, toDesignator: other.concept.codingSchemeDesignator) {
            return mapped == other.concept
        }
        
        return false
    }
}

// Make all code types conform to CodeEquivalent
extension SNOMEDCode: CodeEquivalent {}
extension LOINCCode: CodeEquivalent {}
extension RadLexCode: CodeEquivalent {}
extension DICOMCode: CodeEquivalent {}
extension UCUMUnit: CodeEquivalent {}
extension CodedConcept: CodeEquivalent {
    public var concept: CodedConcept { self }
}

// MARK: - Convenience Methods

extension CodedConcept {
    /// Map this concept to another coding scheme
    /// - Parameter targetScheme: The target coding scheme
    /// - Returns: The equivalent concept, or nil if no mapping exists
    public func map(to targetScheme: CodingSchemeDesignator) -> CodedConcept? {
        CodeMapper.shared.mapCode(self, to: targetScheme)
    }
    
    /// Get all known equivalent concepts in other coding schemes
    /// - Returns: Dictionary of coding scheme to equivalent concept
    public var equivalentCodes: [String: CodedConcept] {
        CodeMapper.shared.allMappings(for: self)
    }
}
