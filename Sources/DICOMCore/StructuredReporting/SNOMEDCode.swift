/// SNOMEDCode - SNOMED Clinical Terms support
///
/// Provides specialized types and common codes for SNOMED CT (Systematized Nomenclature of Medicine - Clinical Terms).
/// SNOMED CT is the most comprehensive healthcare terminology standard in the world.
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: SNOMED International - https://www.snomed.org/
///
/// NEMA-verified: 2026a, checked 2026-09-25 — SNOMED CT is outside NEMA's scope; the check was against every SCT code used in PS3.16 2026a. Of 89 constants, 65 appear in PS3.16: 56 with the same meaning and 9 with a PS3.16 synonym (Upper limb, Lower limb, Thyroid, Bone, occlusion, dilatation, Diagnostic ultrasonography, No change, Thoracic cavity); 24 do not appear and were not verified. `tumor` and `neoplasm` share concept 108369006 (a documented duplicate).

/// A SNOMED CT code with associated metadata
///
/// SNOMED CT codes are numeric identifiers that represent clinical concepts.
/// This type provides a type-safe way to work with SNOMED concepts.
///
/// Example:
/// ```swift
/// let liver = SNOMEDCode.liver
/// print(liver.concept.description) // "(10200004, SCT, "Liver")"
/// ```
public struct SNOMEDCode: Sendable, Equatable, Hashable {
    /// The coded concept representation
    public let concept: CodedConcept
    
    /// The SNOMED CT concept ID (numeric portion)
    public var conceptId: String { concept.codeValue }
    
    /// The fully specified name (FSN) or preferred term
    public var displayName: String { concept.codeMeaning }
    
    /// Creates a SNOMED code from a concept ID and display name
    /// - Parameters:
    ///   - conceptId: The SNOMED CT concept identifier (numeric)
    ///   - displayName: The preferred term or fully specified name
    public init(conceptId: String, displayName: String) {
        self.concept = CodedConcept(
            codeValue: conceptId,
            scheme: .SCT,
            codeMeaning: displayName
        )
    }
    
    /// Creates a SNOMED code from an existing CodedConcept
    /// - Parameter concept: A coded concept using SCT or SRT designator
    /// - Returns: nil if the concept is not a SNOMED code
    public init?(concept: CodedConcept) {
        guard concept.isSNOMED else { return nil }
        self.concept = concept
    }
}

// MARK: - CustomStringConvertible

extension SNOMEDCode: CustomStringConvertible {
    public var description: String {
        concept.description
    }
}

// MARK: - Anatomical Locations

extension SNOMEDCode {
    // MARK: - Body Regions
    
    /// Head (69536005)
    // MARK: - Measurement concepts (PS3.16 2026a, e.g. CID 7470 Linear Measurement, 7471 Area, 7472 Volume)
    //
    // Added 2026-09-25 (P9): the SNOMED CT concepts SR measurement templates name,
    // which used to be mis-registered as DCM codes in `DICOMCode`.

    /// Diameter (81827009)
    public static let diameter = SNOMEDCode(conceptId: "81827009", displayName: "Diameter")
    /// Long Axis (103339001)
    public static let longAxis = SNOMEDCode(conceptId: "103339001", displayName: "Long Axis")
    /// Short Axis (103340004)
    public static let shortAxis = SNOMEDCode(conceptId: "103340004", displayName: "Short Axis")
    /// Perpendicular Axis (131189007)
    public static let perpendicularAxis = SNOMEDCode(conceptId: "131189007", displayName: "Perpendicular Axis")
    /// Length (410668003)
    public static let length = SNOMEDCode(conceptId: "410668003", displayName: "Length")
    /// Width (103355008)
    public static let width = SNOMEDCode(conceptId: "103355008", displayName: "Width")
    /// Area (42798000)
    public static let area = SNOMEDCode(conceptId: "42798000", displayName: "Area")
    /// Volume (118565006)
    public static let volume = SNOMEDCode(conceptId: "118565006", displayName: "Volume")
    /// Circumference (74551000)
    public static let circumference = SNOMEDCode(conceptId: "74551000", displayName: "Circumference")
    /// Perimeter (131191004)
    public static let perimeter = SNOMEDCode(conceptId: "131191004", displayName: "Perimeter")
    /// Mode (373100007)
    public static let mode = SNOMEDCode(conceptId: "373100007", displayName: "Mode")

    public static let head = SNOMEDCode(conceptId: "69536005", displayName: "Head")
    
    /// Neck (45048000)
    public static let neck = SNOMEDCode(conceptId: "45048000", displayName: "Neck")
    
    /// Chest (51185008)
    public static let chest = SNOMEDCode(conceptId: "51185008", displayName: "Chest")
    
    /// Thorax (43799004)
    public static let thorax = SNOMEDCode(conceptId: "43799004", displayName: "Thorax")
    
    /// Abdomen (818983003)
    public static let abdomen = SNOMEDCode(conceptId: "818983003", displayName: "Abdomen")
    
    /// Pelvis (816092008)
    public static let pelvis = SNOMEDCode(conceptId: "816092008", displayName: "Pelvis")
    
    /// Upper extremity (53120007)
    public static let upperExtremity = SNOMEDCode(conceptId: "53120007", displayName: "Upper extremity")
    
    /// Lower extremity (61685007)
    public static let lowerExtremity = SNOMEDCode(conceptId: "61685007", displayName: "Lower extremity")
    
    /// Spine (421060004)
    public static let spine = SNOMEDCode(conceptId: "421060004", displayName: "Spine")
    
    // MARK: - Major Organs
    
    /// Brain (12738006)
    public static let brain = SNOMEDCode(conceptId: "12738006", displayName: "Brain")
    
    /// Heart (80891009)
    public static let heart = SNOMEDCode(conceptId: "80891009", displayName: "Heart")
    
    /// Lung (39607008)
    public static let lung = SNOMEDCode(conceptId: "39607008", displayName: "Lung")
    
    /// Right lung (3341006)
    public static let rightLung = SNOMEDCode(conceptId: "3341006", displayName: "Right lung")
    
    /// Left lung (44029006)
    public static let leftLung = SNOMEDCode(conceptId: "44029006", displayName: "Left lung")
    
    /// Liver (10200004)
    public static let liver = SNOMEDCode(conceptId: "10200004", displayName: "Liver")
    
    /// Kidney (64033007)
    public static let kidney = SNOMEDCode(conceptId: "64033007", displayName: "Kidney")
    
    /// Right kidney (9846003)
    public static let rightKidney = SNOMEDCode(conceptId: "9846003", displayName: "Right kidney")
    
    /// Left kidney (18639004)
    public static let leftKidney = SNOMEDCode(conceptId: "18639004", displayName: "Left kidney")
    
    /// Spleen (78961009)
    public static let spleen = SNOMEDCode(conceptId: "78961009", displayName: "Spleen")
    
    /// Pancreas (15776009)
    public static let pancreas = SNOMEDCode(conceptId: "15776009", displayName: "Pancreas")
    
    /// Stomach (69695003)
    public static let stomach = SNOMEDCode(conceptId: "69695003", displayName: "Stomach")
    
    /// Small intestine (30315005)
    public static let smallIntestine = SNOMEDCode(conceptId: "30315005", displayName: "Small intestine")
    
    /// Large intestine (14742008)
    public static let largeIntestine = SNOMEDCode(conceptId: "14742008", displayName: "Large intestine")
    
    /// Colon (71854001)
    public static let colon = SNOMEDCode(conceptId: "71854001", displayName: "Colon")
    
    /// Bladder (89837001)
    public static let bladder = SNOMEDCode(conceptId: "89837001", displayName: "Bladder")
    
    /// Prostate (41216001)
    public static let prostate = SNOMEDCode(conceptId: "41216001", displayName: "Prostate")
    
    /// Uterus (35039007)
    public static let uterus = SNOMEDCode(conceptId: "35039007", displayName: "Uterus")
    
    /// Ovary (15497006)
    public static let ovary = SNOMEDCode(conceptId: "15497006", displayName: "Ovary")
    
    /// Thyroid gland (69748006)
    public static let thyroidGland = SNOMEDCode(conceptId: "69748006", displayName: "Thyroid gland")
    
    // MARK: - Breast
    
    /// Breast (76752008)
    public static let breast = SNOMEDCode(conceptId: "76752008", displayName: "Breast")
    
    /// Right breast (73056007)
    public static let rightBreast = SNOMEDCode(conceptId: "73056007", displayName: "Right breast")
    
    /// Left breast (80248007)
    public static let leftBreast = SNOMEDCode(conceptId: "80248007", displayName: "Left breast")
    
    // MARK: - Bones
    
    /// Bone structure (272673000)
    public static let bone = SNOMEDCode(conceptId: "272673000", displayName: "Bone structure")
    
    /// Skull (89546000)
    public static let skull = SNOMEDCode(conceptId: "89546000", displayName: "Skull")
    
    /// Vertebral column (44300000)
    public static let vertebralColumn = SNOMEDCode(conceptId: "44300000", displayName: "Vertebral column")
    
    /// Rib (113197003)
    public static let rib = SNOMEDCode(conceptId: "113197003", displayName: "Rib")
    
    /// Femur (71341001)
    public static let femur = SNOMEDCode(conceptId: "71341001", displayName: "Femur")
    
    /// Humerus (85050009)
    public static let humerus = SNOMEDCode(conceptId: "85050009", displayName: "Humerus")
    
    // MARK: - Vasculature
    
    /// Aorta (15825003)
    public static let aorta = SNOMEDCode(conceptId: "15825003", displayName: "Aorta")
    
    /// Carotid artery (69105007)
    public static let carotidArtery = SNOMEDCode(conceptId: "69105007", displayName: "Carotid artery")
    
    /// Coronary artery (41801008)
    public static let coronaryArtery = SNOMEDCode(conceptId: "41801008", displayName: "Coronary artery")
}

// MARK: - Laterality

extension SNOMEDCode {
    /// Right (24028007)
    public static let right = SNOMEDCode(conceptId: "24028007", displayName: "Right")
    
    /// Left (7771000)
    public static let left = SNOMEDCode(conceptId: "7771000", displayName: "Left")
    
    /// Bilateral (51440002)
    public static let bilateral = SNOMEDCode(conceptId: "51440002", displayName: "Bilateral")
    
    /// Unilateral (66459002)
    public static let unilateral = SNOMEDCode(conceptId: "66459002", displayName: "Unilateral")
    
    /// Midline (260528009)
    public static let midline = SNOMEDCode(conceptId: "260528009", displayName: "Midline")
}

// MARK: - Common Findings

extension SNOMEDCode {
    // MARK: - General Findings
    
    /// Mass (4147007)
    public static let mass = SNOMEDCode(conceptId: "4147007", displayName: "Mass")
    
    /// Lesion (52988006)
    public static let lesion = SNOMEDCode(conceptId: "52988006", displayName: "Lesion")
    
    /// Nodule (27925004)
    public static let nodule = SNOMEDCode(conceptId: "27925004", displayName: "Nodule")
    
    /// Cyst (441457006)
    public static let cyst = SNOMEDCode(conceptId: "441457006", displayName: "Cyst")
    
    /// Calcification (36222007)
    public static let calcification = SNOMEDCode(conceptId: "36222007", displayName: "Calcification")
    
    /// Edema (267038008)
    public static let edema = SNOMEDCode(conceptId: "267038008", displayName: "Edema")
    
    /// Hemorrhage (50960005)
    public static let hemorrhage = SNOMEDCode(conceptId: "50960005", displayName: "Hemorrhage")
    
    /// Inflammation (257552002)
    public static let inflammation = SNOMEDCode(conceptId: "257552002", displayName: "Inflammation")
    
    /// Necrosis (6574001)
    public static let necrosis = SNOMEDCode(conceptId: "6574001", displayName: "Necrosis")
    
    /// Stenosis (415582006)
    public static let stenosis = SNOMEDCode(conceptId: "415582006", displayName: "Stenosis")
    
    /// Obstruction (26036001)
    public static let obstruction = SNOMEDCode(conceptId: "26036001", displayName: "Obstruction")
    
    /// Effusion (35013009)
    public static let effusion = SNOMEDCode(conceptId: "35013009", displayName: "Effusion")
    
    /// Fracture (125605004)
    public static let fracture = SNOMEDCode(conceptId: "125605004", displayName: "Fracture")
    
    /// Tumor (108369006)
    public static let tumor = SNOMEDCode(conceptId: "108369006", displayName: "Tumor")
    
    /// Metastasis (128462008)
    public static let metastasis = SNOMEDCode(conceptId: "128462008", displayName: "Metastasis")
    
    /// Neoplasm (108369006)
    public static let neoplasm = SNOMEDCode(conceptId: "108369006", displayName: "Neoplasm")
    
    /// Atrophy (13331008)
    public static let atrophy = SNOMEDCode(conceptId: "13331008", displayName: "Atrophy")
    
    /// Hypertrophy (56246009)
    public static let hypertrophy = SNOMEDCode(conceptId: "56246009", displayName: "Hypertrophy")
    
    /// Dilation (25322007)
    public static let dilation = SNOMEDCode(conceptId: "25322007", displayName: "Dilation")
    
    /// Compression (71173004)
    public static let compression = SNOMEDCode(conceptId: "71173004", displayName: "Compression")
    
    /// Abnormal (263654008)
    public static let abnormal = SNOMEDCode(conceptId: "263654008", displayName: "Abnormal")
    
    /// Normal (17621005)
    public static let normal = SNOMEDCode(conceptId: "17621005", displayName: "Normal")
    
    // MARK: - Severity
    
    /// Mild (255604002)
    public static let mild = SNOMEDCode(conceptId: "255604002", displayName: "Mild")
    
    /// Moderate (6736007)
    public static let moderate = SNOMEDCode(conceptId: "6736007", displayName: "Moderate")
    
    /// Severe (24484000)
    public static let severe = SNOMEDCode(conceptId: "24484000", displayName: "Severe")
}

// MARK: - Common Procedures

extension SNOMEDCode {
    /// Computed tomography (77477000)
    public static let computedTomography = SNOMEDCode(conceptId: "77477000", displayName: "Computed tomography")
    
    /// Magnetic resonance imaging (113091000)
    public static let magneticResonanceImaging = SNOMEDCode(conceptId: "113091000", displayName: "Magnetic resonance imaging")
    
    /// Radiography (363680008)
    public static let radiography = SNOMEDCode(conceptId: "363680008", displayName: "Radiography")
    
    /// Ultrasonography (16310003)
    public static let ultrasonography = SNOMEDCode(conceptId: "16310003", displayName: "Ultrasonography")
    
    /// Positron emission tomography (82918005)
    public static let positronEmissionTomography = SNOMEDCode(conceptId: "82918005", displayName: "Positron emission tomography")
    
    /// Mammography (71651007)
    public static let mammography = SNOMEDCode(conceptId: "71651007", displayName: "Mammography")
    
    /// Fluoroscopy (44491008)
    public static let fluoroscopy = SNOMEDCode(conceptId: "44491008", displayName: "Fluoroscopy")
    
    /// Nuclear medicine procedure (363687004)
    public static let nuclearMedicine = SNOMEDCode(conceptId: "363687004", displayName: "Nuclear medicine procedure")
    
    /// Biopsy (86273004)
    public static let biopsy = SNOMEDCode(conceptId: "86273004", displayName: "Biopsy")
}

// MARK: - Qualifiers

extension SNOMEDCode {
    /// Present (52101004)
    public static let present = SNOMEDCode(conceptId: "52101004", displayName: "Present")
    
    /// Absent (2667000)
    public static let absent = SNOMEDCode(conceptId: "2667000", displayName: "Absent")
    
    /// Unknown (261665006)
    public static let unknown = SNOMEDCode(conceptId: "261665006", displayName: "Unknown")
    
    /// Not applicable (385432009)
    public static let notApplicable = SNOMEDCode(conceptId: "385432009", displayName: "Not applicable")
    
    /// Increased (35105006)
    public static let increased = SNOMEDCode(conceptId: "35105006", displayName: "Increased")
    
    /// Decreased (1250004)
    public static let decreased = SNOMEDCode(conceptId: "1250004", displayName: "Decreased")
    
    /// Unchanged (260388006)
    public static let unchanged = SNOMEDCode(conceptId: "260388006", displayName: "Unchanged")
    
    /// Improved (385633008)
    public static let improved = SNOMEDCode(conceptId: "385633008", displayName: "Improved")
    
    /// Worsened (230993007)
    public static let worsened = SNOMEDCode(conceptId: "230993007", displayName: "Worsened")
}

// MARK: - CodedConcept Convenience

extension CodedConcept {
    /// Create a CodedConcept from a SNOMEDCode
    /// - Parameter snomed: The SNOMED code
    /// - Returns: A coded concept with SCT designator
    public init(snomed: SNOMEDCode) {
        self = snomed.concept
    }
    
    /// Attempt to convert this coded concept to a SNOMEDCode
    /// - Returns: A SNOMEDCode if this is a SNOMED concept, nil otherwise
    public var asSNOMED: SNOMEDCode? {
        SNOMEDCode(concept: self)
    }
}
