/// RadLexCode - RadLex Radiology Lexicon support
///
/// Provides specialized types and common codes for RadLex, the comprehensive
/// radiology lexicon developed by the RSNA (Radiological Society of North America).
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: RadLex.org - https://radlex.org/
///
/// NEMA-verified: 2026a, checked 2026-09-25 — RadLex is outside NEMA's scope, and none of the 70 RID codes here is used in any PS3.16 2026a context group (PS3.16 uses 75 other RadLex codes), so nothing in this file could be verified against the standard.

/// A RadLex code with associated metadata
///
/// RadLex codes are identifiers that represent radiology-specific concepts
/// including imaging procedures, anatomical structures, and radiological findings.
///
/// Example:
/// ```swift
/// let ctScan = RadLexCode.computedTomography
/// print(ctScan.concept.description) // "(RID10321, RADLEX, "Computed tomography")"
/// ```
public struct RadLexCode: Sendable, Equatable, Hashable {
    /// The coded concept representation
    public let concept: CodedConcept
    
    /// The RadLex ID (RID)
    public var radlexId: String { concept.codeValue }
    
    /// The preferred name
    public var preferredName: String { concept.codeMeaning }
    
    /// Creates a RadLex code from a RadLex ID and preferred name
    /// - Parameters:
    ///   - radlexId: The RadLex ID (e.g., "RID10321")
    ///   - preferredName: The preferred name
    public init(radlexId: String, preferredName: String) {
        self.concept = CodedConcept(
            codeValue: radlexId,
            scheme: .RADLEX,
            codeMeaning: preferredName
        )
    }
    
    /// Creates a RadLex code from an existing CodedConcept
    /// - Parameter concept: A coded concept using RADLEX designator
    /// - Returns: nil if the concept is not a RadLex code
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == CodingSchemeDesignator.RADLEX.rawValue else {
            return nil
        }
        self.concept = concept
    }
}

// MARK: - CustomStringConvertible

extension RadLexCode: CustomStringConvertible {
    public var description: String {
        concept.description
    }
}

// MARK: - Imaging Modalities (Playbook)

extension RadLexCode {
    /// Computed tomography (RID10321)
    public static let computedTomography = RadLexCode(radlexId: "RID10321", preferredName: "Computed tomography")
    
    /// Magnetic resonance imaging (RID10312)
    public static let magneticResonanceImaging = RadLexCode(radlexId: "RID10312", preferredName: "Magnetic resonance imaging")
    
    /// Radiography (RID10345)
    public static let radiography = RadLexCode(radlexId: "RID10345", preferredName: "Radiography")
    
    /// Mammography (RID10357)
    public static let mammography = RadLexCode(radlexId: "RID10357", preferredName: "Mammography")
    
    /// Ultrasound (RID10326)
    public static let ultrasound = RadLexCode(radlexId: "RID10326", preferredName: "Ultrasound")
    
    /// Nuclear medicine (RID10330)
    public static let nuclearMedicine = RadLexCode(radlexId: "RID10330", preferredName: "Nuclear medicine")
    
    /// Positron emission tomography (RID10337)
    public static let petImaging = RadLexCode(radlexId: "RID10337", preferredName: "Positron emission tomography")
    
    /// Fluoroscopy (RID10361)
    public static let fluoroscopy = RadLexCode(radlexId: "RID10361", preferredName: "Fluoroscopy")
    
    /// Digital subtraction angiography (RID10397)
    public static let digitalSubtractionAngiography = RadLexCode(radlexId: "RID10397", preferredName: "Digital subtraction angiography")
    
    /// Interventional radiology (RID49555)
    public static let interventionalRadiology = RadLexCode(radlexId: "RID49555", preferredName: "Interventional radiology")
}

// MARK: - Anatomical Structures

extension RadLexCode {
    // MARK: - Body Regions
    
    /// Head (RID9080)
    public static let head = RadLexCode(radlexId: "RID9080", preferredName: "Head")
    
    /// Neck (RID7488)
    public static let neck = RadLexCode(radlexId: "RID7488", preferredName: "Neck")
    
    /// Chest (RID1243)
    public static let chest = RadLexCode(radlexId: "RID1243", preferredName: "Chest")
    
    /// Abdomen (RID56)
    public static let abdomen = RadLexCode(radlexId: "RID56", preferredName: "Abdomen")
    
    /// Pelvis (RID2507)
    public static let pelvis = RadLexCode(radlexId: "RID2507", preferredName: "Pelvis")
    
    /// Spine (RID7741)
    public static let spine = RadLexCode(radlexId: "RID7741", preferredName: "Spine")
    
    // MARK: - Organs
    
    /// Brain (RID6434)
    public static let brain = RadLexCode(radlexId: "RID6434", preferredName: "Brain")
    
    /// Lung (RID1301)
    public static let lung = RadLexCode(radlexId: "RID1301", preferredName: "Lung")
    
    /// Heart (RID1385)
    public static let heart = RadLexCode(radlexId: "RID1385", preferredName: "Heart")
    
    /// Liver (RID58)
    public static let liver = RadLexCode(radlexId: "RID58", preferredName: "Liver")
    
    /// Kidney (RID205)
    public static let kidney = RadLexCode(radlexId: "RID205", preferredName: "Kidney")
    
    /// Spleen (RID86)
    public static let spleen = RadLexCode(radlexId: "RID86", preferredName: "Spleen")
    
    /// Pancreas (RID170)
    public static let pancreas = RadLexCode(radlexId: "RID170", preferredName: "Pancreas")
    
    /// Gallbladder (RID187)
    public static let gallbladder = RadLexCode(radlexId: "RID187", preferredName: "Gallbladder")
    
    /// Adrenal gland (RID88)
    public static let adrenalGland = RadLexCode(radlexId: "RID88", preferredName: "Adrenal gland")
    
    /// Prostate (RID343)
    public static let prostate = RadLexCode(radlexId: "RID343", preferredName: "Prostate")
    
    /// Breast (RID29897)
    public static let breast = RadLexCode(radlexId: "RID29897", preferredName: "Breast")
    
    /// Thyroid gland (RID7578)
    public static let thyroidGland = RadLexCode(radlexId: "RID7578", preferredName: "Thyroid gland")
}

// MARK: - Common Radiology Findings

extension RadLexCode {
    // MARK: - General Findings
    
    /// Mass (RID3874)
    public static let mass = RadLexCode(radlexId: "RID3874", preferredName: "Mass")
    
    /// Nodule (RID3875)
    public static let nodule = RadLexCode(radlexId: "RID3875", preferredName: "Nodule")
    
    /// Lesion (RID38780)
    public static let lesion = RadLexCode(radlexId: "RID38780", preferredName: "Lesion")
    
    /// Cyst (RID3882)
    public static let cyst = RadLexCode(radlexId: "RID3882", preferredName: "Cyst")
    
    /// Calcification (RID5196)
    public static let calcification = RadLexCode(radlexId: "RID5196", preferredName: "Calcification")
    
    /// Enhancement (RID28691)
    public static let enhancement = RadLexCode(radlexId: "RID28691", preferredName: "Enhancement")
    
    /// Consolidation (RID28540)
    public static let consolidation = RadLexCode(radlexId: "RID28540", preferredName: "Consolidation")
    
    /// Ground glass opacity (RID28754)
    public static let groundGlassOpacity = RadLexCode(radlexId: "RID28754", preferredName: "Ground glass opacity")
    
    /// Atelectasis (RID28496)
    public static let atelectasis = RadLexCode(radlexId: "RID28496", preferredName: "Atelectasis")
    
    /// Pneumothorax (RID4872)
    public static let pneumothorax = RadLexCode(radlexId: "RID4872", preferredName: "Pneumothorax")
    
    /// Pleural effusion (RID4890)
    public static let pleuralEffusion = RadLexCode(radlexId: "RID4890", preferredName: "Pleural effusion")
    
    /// Cardiomegaly (RID5361)
    public static let cardiomegaly = RadLexCode(radlexId: "RID5361", preferredName: "Cardiomegaly")
    
    /// Stenosis (RID4640)
    public static let stenosis = RadLexCode(radlexId: "RID4640", preferredName: "Stenosis")
    
    /// Aneurysm (RID4648)
    public static let aneurysm = RadLexCode(radlexId: "RID4648", preferredName: "Aneurysm")
    
    /// Thrombus (RID4649)
    public static let thrombus = RadLexCode(radlexId: "RID4649", preferredName: "Thrombus")
    
    /// Hemorrhage (RID4697)
    public static let hemorrhage = RadLexCode(radlexId: "RID4697", preferredName: "Hemorrhage")
    
    /// Edema (RID4696)
    public static let edema = RadLexCode(radlexId: "RID4696", preferredName: "Edema")
    
    /// Fracture (RID5325)
    public static let fracture = RadLexCode(radlexId: "RID5325", preferredName: "Fracture")
    
    /// Degenerative changes (RID5363)
    public static let degenerativeChanges = RadLexCode(radlexId: "RID5363", preferredName: "Degenerative changes")
    
    /// Metastasis (RID5231)
    public static let metastasis = RadLexCode(radlexId: "RID5231", preferredName: "Metastasis")
    
    /// Lymphadenopathy (RID3890)
    public static let lymphadenopathy = RadLexCode(radlexId: "RID3890", preferredName: "Lymphadenopathy")
}

// MARK: - Qualitative Descriptors

extension RadLexCode {
    /// Well-defined (RID5706)
    public static let wellDefined = RadLexCode(radlexId: "RID5706", preferredName: "Well-defined")
    
    /// Ill-defined (RID5707)
    public static let illDefined = RadLexCode(radlexId: "RID5707", preferredName: "Ill-defined")
    
    /// Homogeneous (RID5715)
    public static let homogeneous = RadLexCode(radlexId: "RID5715", preferredName: "Homogeneous")
    
    /// Heterogeneous (RID5716)
    public static let heterogeneous = RadLexCode(radlexId: "RID5716", preferredName: "Heterogeneous")
    
    /// Spiculated (RID5721)
    public static let spiculated = RadLexCode(radlexId: "RID5721", preferredName: "Spiculated")
    
    /// Round (RID5798)
    public static let round = RadLexCode(radlexId: "RID5798", preferredName: "Round")
    
    /// Oval (RID5799)
    public static let oval = RadLexCode(radlexId: "RID5799", preferredName: "Oval")
    
    /// Irregular (RID5800)
    public static let irregular = RadLexCode(radlexId: "RID5800", preferredName: "Irregular")
    
    /// Lobulated (RID5801)
    public static let lobulated = RadLexCode(radlexId: "RID5801", preferredName: "Lobulated")
}

// MARK: - Temporal Descriptors

extension RadLexCode {
    /// Acute (RID5733)
    public static let acute = RadLexCode(radlexId: "RID5733", preferredName: "Acute")
    
    /// Subacute (RID5734)
    public static let subacute = RadLexCode(radlexId: "RID5734", preferredName: "Subacute")
    
    /// Chronic (RID5735)
    public static let chronic = RadLexCode(radlexId: "RID5735", preferredName: "Chronic")
    
    /// New (RID5751)
    public static let new = RadLexCode(radlexId: "RID5751", preferredName: "New")
    
    /// Stable (RID5752)
    public static let stable = RadLexCode(radlexId: "RID5752", preferredName: "Stable")
    
    /// Improved (RID5753)
    public static let improved = RadLexCode(radlexId: "RID5753", preferredName: "Improved")
    
    /// Worsened (RID5754)
    public static let worsened = RadLexCode(radlexId: "RID5754", preferredName: "Worsened")
    
    /// Resolved (RID5755)
    public static let resolved = RadLexCode(radlexId: "RID5755", preferredName: "Resolved")
}

// MARK: - Size Descriptors

extension RadLexCode {
    /// Small (RID5760)
    public static let small = RadLexCode(radlexId: "RID5760", preferredName: "Small")
    
    /// Medium (RID5761)
    public static let medium = RadLexCode(radlexId: "RID5761", preferredName: "Medium")
    
    /// Large (RID5762)
    public static let large = RadLexCode(radlexId: "RID5762", preferredName: "Large")
    
    /// Massive (RID5763)
    public static let massive = RadLexCode(radlexId: "RID5763", preferredName: "Massive")
}

// MARK: - CodedConcept Convenience

extension CodedConcept {
    /// Create a CodedConcept from a RadLexCode
    /// - Parameter radlex: The RadLex code
    /// - Returns: A coded concept with RADLEX designator
    public init(radlex: RadLexCode) {
        self = radlex.concept
    }
    
    /// Attempt to convert this coded concept to a RadLexCode
    /// - Returns: A RadLexCode if this is a RadLex concept, nil otherwise
    public var asRadLex: RadLexCode? {
        RadLexCode(concept: self)
    }
    
    /// Returns whether this concept uses RadLex coding scheme
    public var isRadLex: Bool {
        codingSchemeDesignator == CodingSchemeDesignator.RADLEX.rawValue
    }
}
