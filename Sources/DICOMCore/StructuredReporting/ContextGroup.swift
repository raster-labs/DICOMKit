/// ContextGroup - DICOM Context Group support (PS3.16)
///
/// Provides structures for working with DICOM Context Groups (CIDs) which
/// define sets of coded concepts for specific purposes in DICOM.
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: PS3.16 Annex B - DCMR Context Group Definitions
///
/// NEMA-verified: 2026a, checked 2026-09-25 — the 10 groups below are generated from the
/// PS3.16 2026a CID tables (matched by `table_CID_<n>`, with "Include CID" rows expanded):
/// name, Type, Version and every member (scheme, code value, code meaning).

#if canImport(Foundation)
import Foundation
#endif

/// A DICOM Context Group definition
///
/// Context Groups (CIDs) define sets of coded concepts that are valid
/// for specific purposes within DICOM. For example, CID 244 defines
/// the valid codes for laterality.
///
/// Example:
/// ```swift
/// let laterality = ContextGroup.laterality
/// if laterality.contains(CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right")) {
///     print("Valid laterality code")
/// }
/// ```
public struct ContextGroup: Sendable, Equatable {
    /// The Context Identifier (CID) number
    public let cid: Int
    
    /// The name of the context group
    public let name: String
    
    /// Whether this context group is extensible (allows additional codes)
    public let isExtensible: Bool
    
    /// The version of the context group
    public let version: String?
    
    /// The coded concepts that are members of this context group
    public let members: [CodedConcept]
    
    /// Creates a context group
    /// - Parameters:
    ///   - cid: The Context Identifier number
    ///   - name: The name of the context group
    ///   - isExtensible: Whether additional codes are allowed (default: true)
    ///   - version: Optional version string
    ///   - members: The coded concepts in this group
    public init(
        cid: Int,
        name: String,
        isExtensible: Bool = true,
        version: String? = nil,
        members: [CodedConcept]
    ) {
        self.cid = cid
        self.name = name
        self.isExtensible = isExtensible
        self.version = version
        self.members = members
    }
    
    /// Check if a coded concept is a member of this context group
    /// - Parameter concept: The coded concept to check
    /// - Returns: true if the concept is in this context group
    public func contains(_ concept: CodedConcept) -> Bool {
        members.contains(concept)
    }
    
    /// Validate a coded concept against this context group
    /// - Parameter concept: The coded concept to validate
    /// - Returns: ValidationResult indicating whether the concept is valid
    public func validate(_ concept: CodedConcept) -> ValidationResult {
        if contains(concept) {
            return .valid
        }
        
        if isExtensible {
            return .extensionCode
        }
        
        return .invalid(reason: "Code \(concept.codeValue) is not a member of CID \(cid) (\(name))")
    }
    
    /// Result of validating a concept against a context group
    public enum ValidationResult: Sendable, Equatable {
        /// The concept is a defined member of the context group
        case valid
        /// The concept is not a defined member, but the group is extensible
        case extensionCode
        /// The concept is invalid for this context group
        case invalid(reason: String)
        
        /// Whether the concept can be used (valid or extension)
        public var isAcceptable: Bool {
            switch self {
            case .valid, .extensionCode:
                return true
            case .invalid:
                return false
            }
        }
    }
}

// MARK: - CustomStringConvertible

extension ContextGroup: CustomStringConvertible {
    public var description: String {
        let extensible = isExtensible ? "extensible" : "non-extensible"
        return "CID \(cid) - \(name) (\(extensible), \(members.count) codes)"
    }
}

// MARK: - CID 244: Laterality

extension ContextGroup {
    /// CID 244 - Laterality
    ///
    /// Laterality of a body part. Includes CID 247 (Right, Left).
    /// PS3.16 2026a Table CID 244: Non-Extensible, Version 20030108, 4 codes.
    public static let laterality = ContextGroup(
        cid: 244,
        name: "Laterality",
        isExtensible: false,
        version: "20030108",
        members: [
            CodedConcept(codeValue: "51440002", scheme: .SCT, codeMeaning: "Bilateral"),
            CodedConcept(codeValue: "66459002", scheme: .SCT, codeMeaning: "Unilateral"),
            CodedConcept(codeValue: "24028007", scheme: .SCT, codeMeaning: "Right"),
            CodedConcept(codeValue: "7771000", scheme: .SCT, codeMeaning: "Left"),
        ]
    )
}

// MARK: - CID 7021: Measurement Report Document Title

extension ContextGroup {
    /// CID 7021 - Measurement Report Document Title
    ///
    /// Document titles for Measurement Report SR documents.
    /// PS3.16 2026a Table CID 7021: Extensible, Version 20141110, 4 codes.
    public static let measurementReportDocumentTitles = ContextGroup(
        cid: 7021,
        name: "Measurement Report Document Title",
        isExtensible: true,
        version: "20141110",
        members: [
            CodedConcept(codeValue: "126000", scheme: .DCM, codeMeaning: "Imaging Measurement Report"),
            CodedConcept(codeValue: "126001", scheme: .DCM, codeMeaning: "Oncology Measurement Report"),
            CodedConcept(codeValue: "126002", scheme: .DCM, codeMeaning: "Dynamic Contrast MR Measurement Report"),
            CodedConcept(codeValue: "126003", scheme: .DCM, codeMeaning: "PET Measurement Report"),
        ]
    )
}

// MARK: - CID 3600: Relative Time

extension ContextGroup {
    /// CID 3600 - Relative Time
    ///
    /// Temporal relation of an event to a reference: Before, During, After.
    /// PS3.16 2026a Table CID 3600: Extensible, Version 20030327, 3 codes.
    public static let relativeTime = ContextGroup(
        cid: 3600,
        name: "Relative Time",
        isExtensible: true,
        version: "20030327",
        members: [
            CodedConcept(codeValue: "272113006", scheme: .SCT, codeMeaning: "Before"),
            CodedConcept(codeValue: "272114000", scheme: .SCT, codeMeaning: "During"),
            CodedConcept(codeValue: "288563008", scheme: .SCT, codeMeaning: "After"),
        ]
    )
}

// MARK: - CID 4031: Common Anatomic Region

extension ContextGroup {
    /// CID 4031 - Common Anatomic Region
    ///
    /// Anatomic regions commonly used as finding sites.
    /// PS3.16 2026a Table CID 4031: Extensible, Version 20250709, 119 codes.
    public static let commonAnatomicRegion = ContextGroup(
        cid: 4031,
        name: "Common Anatomic Region",
        isExtensible: true,
        version: "20250709",
        members: [
            CodedConcept(codeValue: "818981001", scheme: .SCT, codeMeaning: "Abdomen"),
            CodedConcept(codeValue: "818982008", scheme: .SCT, codeMeaning: "Abdomen and Pelvis"),
            CodedConcept(codeValue: "85856004", scheme: .SCT, codeMeaning: "Acromioclavicular joint"),
            CodedConcept(codeValue: "70258002", scheme: .SCT, codeMeaning: "Ankle joint"),
            CodedConcept(codeValue: "53505006", scheme: .SCT, codeMeaning: "Anus"),
            CodedConcept(codeValue: "86598002", scheme: .SCT, codeMeaning: "Apex of Lung"),
            CodedConcept(codeValue: "28273000", scheme: .SCT, codeMeaning: "Bile duct"),
            CodedConcept(codeValue: "34707002", scheme: .SCT, codeMeaning: "Biliary tract"),
            CodedConcept(codeValue: "89837001", scheme: .SCT, codeMeaning: "Bladder"),
            CodedConcept(codeValue: "72001000", scheme: .SCT, codeMeaning: "Bone of lower limb"),
            CodedConcept(codeValue: "371195002", scheme: .SCT, codeMeaning: "Bone of upper limb"),
            CodedConcept(codeValue: "76752008", scheme: .SCT, codeMeaning: "Breast"),
            CodedConcept(codeValue: "955009", scheme: .SCT, codeMeaning: "Bronchus"),
            CodedConcept(codeValue: "80144004", scheme: .SCT, codeMeaning: "Calcaneus"),
            CodedConcept(codeValue: "113257007", scheme: .SCT, codeMeaning: "Cardiovascular system"),
            CodedConcept(codeValue: "122494005", scheme: .SCT, codeMeaning: "Cervical spine"),
            CodedConcept(codeValue: "1217257000", scheme: .SCT, codeMeaning: "Cervico-thoracic spine"),
            CodedConcept(codeValue: "816094009", scheme: .SCT, codeMeaning: "Chest"),
            CodedConcept(codeValue: "416775004", scheme: .SCT, codeMeaning: "Chest, Abdomen and Pelvis"),
            CodedConcept(codeValue: "416550000", scheme: .SCT, codeMeaning: "Chest and Abdomen"),
            CodedConcept(codeValue: "51299004", scheme: .SCT, codeMeaning: "Clavicle"),
            CodedConcept(codeValue: "64688005", scheme: .SCT, codeMeaning: "Coccyx"),
            CodedConcept(codeValue: "71854001", scheme: .SCT, codeMeaning: "Colon"),
            CodedConcept(codeValue: "79741001", scheme: .SCT, codeMeaning: "Common bile duct"),
            CodedConcept(codeValue: "38848004", scheme: .SCT, codeMeaning: "Duodenum"),
            CodedConcept(codeValue: "16953009", scheme: .SCT, codeMeaning: "Elbow joint"),
            CodedConcept(codeValue: "38266002", scheme: .SCT, codeMeaning: "Entire body"),
            CodedConcept(codeValue: "32849002", scheme: .SCT, codeMeaning: "Esophagus"),
            CodedConcept(codeValue: "110861005", scheme: .SCT, codeMeaning: "Esophagus, stomach and duodenum"),
            CodedConcept(codeValue: "66019005", scheme: .SCT, codeMeaning: "Extremity"),
            CodedConcept(codeValue: "81745001", scheme: .SCT, codeMeaning: "Eye"),
            CodedConcept(codeValue: "371398005", scheme: .SCT, codeMeaning: "Eye region"),
            CodedConcept(codeValue: "91397008", scheme: .SCT, codeMeaning: "Facial bones"),
            CodedConcept(codeValue: "71341001", scheme: .SCT, codeMeaning: "Femur"),
            CodedConcept(codeValue: "87342007", scheme: .SCT, codeMeaning: "Fibula"),
            CodedConcept(codeValue: "7569003", scheme: .SCT, codeMeaning: "Finger"),
            CodedConcept(codeValue: "56459004", scheme: .SCT, codeMeaning: "Foot"),
            CodedConcept(codeValue: "14975008", scheme: .SCT, codeMeaning: "Forearm"),
            CodedConcept(codeValue: "28231008", scheme: .SCT, codeMeaning: "Gallbladder"),
            CodedConcept(codeValue: "85562004", scheme: .SCT, codeMeaning: "Hand"),
            CodedConcept(codeValue: "69536005", scheme: .SCT, codeMeaning: "Head"),
            CodedConcept(codeValue: "774007", scheme: .SCT, codeMeaning: "Head and Neck"),
            CodedConcept(codeValue: "80891009", scheme: .SCT, codeMeaning: "Heart"),
            CodedConcept(codeValue: "29836001", scheme: .SCT, codeMeaning: "Hip"),
            CodedConcept(codeValue: "24136001", scheme: .SCT, codeMeaning: "Hip Joint"),
            CodedConcept(codeValue: "85050009", scheme: .SCT, codeMeaning: "Humerus"),
            CodedConcept(codeValue: "34516001", scheme: .SCT, codeMeaning: "Ileum"),
            CodedConcept(codeValue: "22356005", scheme: .SCT, codeMeaning: "Ilium"),
            CodedConcept(codeValue: "361078006", scheme: .SCT, codeMeaning: "Internal Auditory Canal"),
            CodedConcept(codeValue: "661005", scheme: .SCT, codeMeaning: "Jaw region"),
            CodedConcept(codeValue: "21306003", scheme: .SCT, codeMeaning: "Jejunum"),
            CodedConcept(codeValue: "72696002", scheme: .SCT, codeMeaning: "Knee"),
            CodedConcept(codeValue: "14742008", scheme: .SCT, codeMeaning: "Large intestine"),
            CodedConcept(codeValue: "4596009", scheme: .SCT, codeMeaning: "Larynx"),
            CodedConcept(codeValue: "303270005", scheme: .SCT, codeMeaning: "Liver and biliary structure"),
            CodedConcept(codeValue: "30021000", scheme: .SCT, codeMeaning: "Lower leg"),
            CodedConcept(codeValue: "61685007", scheme: .SCT, codeMeaning: "Lower limb"),
            CodedConcept(codeValue: "63337009", scheme: .SCT, codeMeaning: "Lower trunk"),
            CodedConcept(codeValue: "122496007", scheme: .SCT, codeMeaning: "Lumbar spine"),
            CodedConcept(codeValue: "1217253001", scheme: .SCT, codeMeaning: "Lumbo-sacral spine"),
            CodedConcept(codeValue: "91609006", scheme: .SCT, codeMeaning: "Mandible"),
            CodedConcept(codeValue: "59066005", scheme: .SCT, codeMeaning: "Mastoid bone"),
            CodedConcept(codeValue: "70925003", scheme: .SCT, codeMeaning: "Maxilla"),
            CodedConcept(codeValue: "72410000", scheme: .SCT, codeMeaning: "Mediastinum"),
            CodedConcept(codeValue: "102292000", scheme: .SCT, codeMeaning: "Muscle of lower limb"),
            CodedConcept(codeValue: "30608006", scheme: .SCT, codeMeaning: "Muscle of upper limb"),
            CodedConcept(codeValue: "74386004", scheme: .SCT, codeMeaning: "Nasal bone"),
            CodedConcept(codeValue: "45048000", scheme: .SCT, codeMeaning: "Neck"),
            CodedConcept(codeValue: "416319003", scheme: .SCT, codeMeaning: "Neck, Chest, Abdomen and Pelvis"),
            CodedConcept(codeValue: "416152001", scheme: .SCT, codeMeaning: "Neck, Chest and Abdomen"),
            CodedConcept(codeValue: "417437006", scheme: .SCT, codeMeaning: "Neck and Chest"),
            CodedConcept(codeValue: "55024004", scheme: .SCT, codeMeaning: "Optic canal"),
            CodedConcept(codeValue: "363654007", scheme: .SCT, codeMeaning: "Orbital structure"),
            CodedConcept(codeValue: "15776009", scheme: .SCT, codeMeaning: "Pancreas"),
            CodedConcept(codeValue: "69930009", scheme: .SCT, codeMeaning: "Pancreatic duct"),
            CodedConcept(codeValue: "110621006", scheme: .SCT, codeMeaning: "Pancreatic duct and bile duct systems"),
            CodedConcept(codeValue: "2095001", scheme: .SCT, codeMeaning: "Paranasal sinus"),
            CodedConcept(codeValue: "45289007", scheme: .SCT, codeMeaning: "Parotid gland"),
            CodedConcept(codeValue: "64234005", scheme: .SCT, codeMeaning: "Patella"),
            CodedConcept(codeValue: "816092008", scheme: .SCT, codeMeaning: "Pelvis"),
            CodedConcept(codeValue: "1231522001", scheme: .SCT, codeMeaning: "Pelvis and lower extremities"),
            CodedConcept(codeValue: "706342009", scheme: .SCT, codeMeaning: "Phantom"),
            CodedConcept(codeValue: "41216001", scheme: .SCT, codeMeaning: "Prostate"),
            CodedConcept(codeValue: "34402009", scheme: .SCT, codeMeaning: "Rectum"),
            CodedConcept(codeValue: "113197003", scheme: .SCT, codeMeaning: "Rib"),
            CodedConcept(codeValue: "1217254007", scheme: .SCT, codeMeaning: "Sacro-coccygeal Spine"),
            CodedConcept(codeValue: "39723000", scheme: .SCT, codeMeaning: "Sacroiliac joint"),
            CodedConcept(codeValue: "54735007", scheme: .SCT, codeMeaning: "Sacrum"),
            CodedConcept(codeValue: "79601000", scheme: .SCT, codeMeaning: "Scapula"),
            CodedConcept(codeValue: "42575006", scheme: .SCT, codeMeaning: "Sella turcica"),
            CodedConcept(codeValue: "58742003", scheme: .SCT, codeMeaning: "Sesamoid bones of foot"),
            CodedConcept(codeValue: "16982005", scheme: .SCT, codeMeaning: "Shoulder"),
            CodedConcept(codeValue: "89546000", scheme: .SCT, codeMeaning: "Skull"),
            CodedConcept(codeValue: "30315005", scheme: .SCT, codeMeaning: "Small intestine"),
            CodedConcept(codeValue: "421060004", scheme: .SCT, codeMeaning: "Spine"),
            CodedConcept(codeValue: "737561001", scheme: .SCT, codeMeaning: "Spine and/or cord"),
            CodedConcept(codeValue: "7844006", scheme: .SCT, codeMeaning: "Sternoclavicular joint"),
            CodedConcept(codeValue: "56873002", scheme: .SCT, codeMeaning: "Sternum"),
            CodedConcept(codeValue: "69695003", scheme: .SCT, codeMeaning: "Stomach"),
            CodedConcept(codeValue: "54019009", scheme: .SCT, codeMeaning: "Submandibular gland"),
            CodedConcept(codeValue: "27949001", scheme: .SCT, codeMeaning: "Tarsal joint"),
            CodedConcept(codeValue: "53620006", scheme: .SCT, codeMeaning: "Temporomandibular joint"),
            CodedConcept(codeValue: "68367000", scheme: .SCT, codeMeaning: "Thigh"),
            CodedConcept(codeValue: "122495006", scheme: .SCT, codeMeaning: "Thoracic spine"),
            CodedConcept(codeValue: "1217256009", scheme: .SCT, codeMeaning: "Thoraco-lumbar spine"),
            CodedConcept(codeValue: "76505004", scheme: .SCT, codeMeaning: "Thumb"),
            CodedConcept(codeValue: "29707007", scheme: .SCT, codeMeaning: "Toe"),
            CodedConcept(codeValue: "44567001", scheme: .SCT, codeMeaning: "Trachea"),
            CodedConcept(codeValue: "22943007", scheme: .SCT, codeMeaning: "Trunk"),
            CodedConcept(codeValue: "40983000", scheme: .SCT, codeMeaning: "Upper arm"),
            CodedConcept(codeValue: "53120007", scheme: .SCT, codeMeaning: "Upper limb"),
            CodedConcept(codeValue: "67734004", scheme: .SCT, codeMeaning: "Upper trunk"),
            CodedConcept(codeValue: "431491007", scheme: .SCT, codeMeaning: "Upper urinary tract"),
            CodedConcept(codeValue: "87953007", scheme: .SCT, codeMeaning: "Ureter"),
            CodedConcept(codeValue: "13648007", scheme: .SCT, codeMeaning: "Urethra"),
            CodedConcept(codeValue: "110639002", scheme: .SCT, codeMeaning: "Uterus and fallopian tubes"),
            CodedConcept(codeValue: "110517009", scheme: .SCT, codeMeaning: "Vertebral column and cranium"),
            CodedConcept(codeValue: "74670003", scheme: .SCT, codeMeaning: "Wrist joint"),
            CodedConcept(codeValue: "13881006", scheme: .SCT, codeMeaning: "Zygoma"),
        ]
    )
}

// MARK: - CID 6144: RECIST Defined Lesion Response

extension ContextGroup {
    /// CID 6144 - RECIST Defined Lesion Response
    ///
    /// Target and non-target lesion response per RECIST.
    /// PS3.16 2026a Table CID 6144: Extensible, Version 20030108, 7 codes.
    public static let recistDefinedLesionResponse = ContextGroup(
        cid: 6144,
        name: "RECIST Defined Lesion Response",
        isExtensible: true,
        version: "20030108",
        members: [
            CodedConcept(codeValue: "112041", scheme: .DCM, codeMeaning: "Target Lesion Complete Response"),
            CodedConcept(codeValue: "112042", scheme: .DCM, codeMeaning: "Target Lesion Partial Response"),
            CodedConcept(codeValue: "112043", scheme: .DCM, codeMeaning: "Target Lesion Progressive Disease"),
            CodedConcept(codeValue: "112044", scheme: .DCM, codeMeaning: "Target Lesion Stable Disease"),
            CodedConcept(codeValue: "112045", scheme: .DCM, codeMeaning: "Non-Target Lesion Complete Response"),
            CodedConcept(codeValue: "112046", scheme: .DCM, codeMeaning: "Non-Target Lesion Incomplete Response or Stable Disease"),
            CodedConcept(codeValue: "112047", scheme: .DCM, codeMeaning: "Non-Target Lesion Progressive Disease"),
        ]
    )
}

// MARK: - CID 7460: Linear Measurement Unit

extension ContextGroup {
    /// CID 7460 - Linear Measurement Unit
    ///
    /// Units for linear measurements.
    /// PS3.16 2026a Table CID 7460: Extensible, Version 20020904, 3 codes.
    public static let linearMeasurementUnit = ContextGroup(
        cid: 7460,
        name: "Linear Measurement Unit",
        isExtensible: true,
        version: "20020904",
        members: [
            CodedConcept(codeValue: "cm", scheme: .UCUM, codeMeaning: "centimeter"),
            CodedConcept(codeValue: "mm", scheme: .UCUM, codeMeaning: "millimeter"),
            CodedConcept(codeValue: "um", scheme: .UCUM, codeMeaning: "micrometer"),
        ]
    )
}

// MARK: - CID 7461: Area Measurement Unit

extension ContextGroup {
    /// CID 7461 - Area Measurement Unit
    ///
    /// Units for area measurements.
    /// PS3.16 2026a Table CID 7461: Extensible, Version 20020904, 3 codes.
    public static let areaMeasurementUnit = ContextGroup(
        cid: 7461,
        name: "Area Measurement Unit",
        isExtensible: true,
        version: "20020904",
        members: [
            CodedConcept(codeValue: "cm2", scheme: .UCUM, codeMeaning: "square centimeter"),
            CodedConcept(codeValue: "mm2", scheme: .UCUM, codeMeaning: "square millimeter"),
            CodedConcept(codeValue: "um2", scheme: .UCUM, codeMeaning: "square micrometer"),
        ]
    )
}

// MARK: - CID 7462: Volume Measurement Unit

extension ContextGroup {
    /// CID 7462 - Volume Measurement Unit
    ///
    /// Units for volume measurements.
    /// PS3.16 2026a Table CID 7462: Extensible, Version 20020904, 4 codes.
    public static let volumeMeasurementUnit = ContextGroup(
        cid: 7462,
        name: "Volume Measurement Unit",
        isExtensible: true,
        version: "20020904",
        members: [
            CodedConcept(codeValue: "dm3", scheme: .UCUM, codeMeaning: "cubic decimeter"),
            CodedConcept(codeValue: "cm3", scheme: .UCUM, codeMeaning: "cubic centimeter"),
            CodedConcept(codeValue: "mm3", scheme: .UCUM, codeMeaning: "cubic millimeter"),
            CodedConcept(codeValue: "um3", scheme: .UCUM, codeMeaning: "cubic micrometer"),
        ]
    )
}

// MARK: - CID 6054: Breast Imaging Finding

extension ContextGroup {
    /// CID 6054 - Breast Imaging Finding
    ///
    /// Breast imaging findings. Includes CIDs 6016, 6057 and 6064.
    /// PS3.16 2026a Table CID 6054: Extensible, Version 20050110, 47 codes.
    public static let breastImagingFinding = ContextGroup(
        cid: 6054,
        name: "Breast Imaging Finding",
        isExtensible: true,
        version: "20050110",
        members: [
            CodedConcept(codeValue: "290084006", scheme: .SCT, codeMeaning: "Breast normal"),
            CodedConcept(codeValue: "309587003", scheme: .SCT, codeMeaning: "Calcification of breast"),
            CodedConcept(codeValue: "40388003", scheme: .SCT, codeMeaning: "Implant"),
            CodedConcept(codeValue: "111459", scheme: .DCM, codeMeaning: "Mass with calcifications"),
            CodedConcept(codeValue: "111099", scheme: .DCM, codeMeaning: "Selected region"),
            CodedConcept(codeValue: "111100", scheme: .DCM, codeMeaning: "Breast geometry"),
            CodedConcept(codeValue: "111101", scheme: .DCM, codeMeaning: "Image Quality"),
            CodedConcept(codeValue: "111102", scheme: .DCM, codeMeaning: "Non-lesion"),
            CodedConcept(codeValue: "24142002", scheme: .SCT, codeMeaning: "Nipple"),
            CodedConcept(codeValue: "129793001", scheme: .SCT, codeMeaning: "Mammography breast density"),
            CodedConcept(codeValue: "129770007", scheme: .SCT, codeMeaning: "Individual Calcification"),
            CodedConcept(codeValue: "129769006", scheme: .SCT, codeMeaning: "Calcification Cluster"),
            CodedConcept(codeValue: "129792006", scheme: .SCT, codeMeaning: "Architectural distortion of breast"),
            CodedConcept(codeValue: "129794007", scheme: .SCT, codeMeaning: "Tubular density"),
            CodedConcept(codeValue: "443808008", scheme: .SCT, codeMeaning: "Intramammary lymph node"),
            CodedConcept(codeValue: "129795008", scheme: .SCT, codeMeaning: "Trabecular thickening of breast"),
            CodedConcept(codeValue: "129715009", scheme: .SCT, codeMeaning: "Breast composition"),
            CodedConcept(codeValue: "129796009", scheme: .SCT, codeMeaning: "Skin retraction of breast"),
            CodedConcept(codeValue: "129797000", scheme: .SCT, codeMeaning: "Skin thickening of breast"),
            CodedConcept(codeValue: "127189005", scheme: .SCT, codeMeaning: "Axillary adenopathy"),
            CodedConcept(codeValue: "95324001", scheme: .SCT, codeMeaning: "Skin lesion"),
            CodedConcept(codeValue: "111111", scheme: .DCM, codeMeaning: "Cooper's ligament changes"),
            CodedConcept(codeValue: "79654002", scheme: .SCT, codeMeaning: "Edema"),
            CodedConcept(codeValue: "111112", scheme: .DCM, codeMeaning: "Mass in the skin"),
            CodedConcept(codeValue: "111113", scheme: .DCM, codeMeaning: "Mass on the skin"),
            CodedConcept(codeValue: "68171009", scheme: .SCT, codeMeaning: "Axillary lymph node"),
            CodedConcept(codeValue: "129788004", scheme: .SCT, codeMeaning: "Mammographic breast mass"),
            CodedConcept(codeValue: "129789007", scheme: .SCT, codeMeaning: "Focal asymmetric breast tissue"),
            CodedConcept(codeValue: "129790003", scheme: .SCT, codeMeaning: "Asymmetric breast tissue"),
            CodedConcept(codeValue: "111287", scheme: .DCM, codeMeaning: "Normal breast tissue"),
            CodedConcept(codeValue: "111425", scheme: .DCM, codeMeaning: "Intraluminal filling defect"),
            CodedConcept(codeValue: "22049009", scheme: .SCT, codeMeaning: "Mammary duct ectasia"),
            CodedConcept(codeValue: "111426", scheme: .DCM, codeMeaning: "Multiple filling defect"),
            CodedConcept(codeValue: "111427", scheme: .DCM, codeMeaning: "Abrupt duct termination"),
            CodedConcept(codeValue: "111428", scheme: .DCM, codeMeaning: "Extravasation"),
            CodedConcept(codeValue: "111429", scheme: .DCM, codeMeaning: "Duct narrowing"),
            CodedConcept(codeValue: "111430", scheme: .DCM, codeMeaning: "Cyst fill"),
            CodedConcept(codeValue: "169254007", scheme: .SCT, codeMeaning: "Ultrasound scan normal"),
            CodedConcept(codeValue: "399294002", scheme: .SCT, codeMeaning: "Cyst of breast"),
            CodedConcept(codeValue: "111460", scheme: .DCM, codeMeaning: "Complex cyst"),
            CodedConcept(codeValue: "111461", scheme: .DCM, codeMeaning: "Intracystic lesion"),
            CodedConcept(codeValue: "111462", scheme: .DCM, codeMeaning: "Solid mass"),
            CodedConcept(codeValue: "59441001", scheme: .SCT, codeMeaning: "Lymph node"),
            CodedConcept(codeValue: "76649007", scheme: .SCT, codeMeaning: "Sebaceous cyst of skin of breast"),
            CodedConcept(codeValue: "111129", scheme: .DCM, codeMeaning: "Clustered microcysts"),
            CodedConcept(codeValue: "111130", scheme: .DCM, codeMeaning: "Complicated cyst"),
            CodedConcept(codeValue: "19227008", scheme: .SCT, codeMeaning: "Foreign body"),
        ]
    )
}

// MARK: - CID 3627: Measurement Type

extension ContextGroup {
    /// CID 3627 - Measurement Type
    ///
    /// How a measured value was obtained: Measured, Estimated, Calculated, and others.
    /// PS3.16 2026a Table CID 3627: Extensible, Version 20060613, 10 codes.
    public static let measurementType = ContextGroup(
        cid: 3627,
        name: "Measurement Type",
        isExtensible: true,
        version: "20060613",
        members: [
            CodedConcept(codeValue: "371912002", scheme: .SCT, codeMeaning: "Best value"),
            CodedConcept(codeValue: "373098007", scheme: .SCT, codeMeaning: "Mean"),
            CodedConcept(codeValue: "373099004", scheme: .SCT, codeMeaning: "Median"),
            CodedConcept(codeValue: "373100007", scheme: .SCT, codeMeaning: "Mode"),
            CodedConcept(codeValue: "371913007", scheme: .SCT, codeMeaning: "Point source measurement"),
            CodedConcept(codeValue: "371914001", scheme: .SCT, codeMeaning: "Peak to peak"),
            CodedConcept(codeValue: "258083009", scheme: .SCT, codeMeaning: "Visual estimation"),
            CodedConcept(codeValue: "414135002", scheme: .SCT, codeMeaning: "Estimated"),
            CodedConcept(codeValue: "258090004", scheme: .SCT, codeMeaning: "Calculated"),
            CodedConcept(codeValue: "258104002", scheme: .SCT, codeMeaning: "Measured"),
        ]
    )
}

// MARK: - Superseded groups

extension ContextGroup {
    /// The pre-2026-09-25 groups carried CID numbers that PS3.16 assigns to other context
    /// groups, and members that PS3.16 does not define. Each is replaced by the real context
    /// group holding the intended concepts, or removed when none exists.

    @available(*, deprecated, renamed: "relativeTime", message: "CID 218 is Quantitative Image Feature; the temporal relations Before/During/After are CID 3600 Relative Time")
    public static var quantitativeTemporalRelation: ContextGroup { relativeTime }

    @available(*, deprecated, renamed: "commonAnatomicRegion", message: "CID 4021 is PET Radiopharmaceutical; anatomic finding sites are CID 4031 Common Anatomic Region")
    public static var findingSite: ContextGroup { commonAnatomicRegion }

    @available(*, deprecated, renamed: "recistDefinedLesionResponse", message: "CID 6147 is Response Criteria (WHO, RECIST, RANO); lesion response codes are CID 6144")
    public static var responseEvaluation: ContextGroup { recistDefinedLesionResponse }

    @available(*, deprecated, message: "CID 7464 is General Region of Interest Measurement Modifier; units are CID 7460 (linear), 7461 (area) and 7462 (volume)")
    public static var roiMeasurementUnits: ContextGroup { linearMeasurementUnit }

    @available(*, unavailable, message: "CID 12301 is Measurement Selection Reason, and PS3.16 has no general Imaging Observations context group; use a finding CID for the body part")
    public static var imagingObservations: ContextGroup { fatalError() }

    @available(*, deprecated, renamed: "measurementType", message: "CID 6024 is Depth; Measured/Estimated/Calculated are CID 3627 Measurement Type")
    public static var derivation: ContextGroup { measurementType }
}

// MARK: - Context Group Registry

/// Registry of known context groups
///
/// Provides lookup and management of DICOM context groups.
///
/// Example:
/// ```swift
/// let registry = ContextGroupRegistry.shared
/// if let laterality = registry.group(forCID: 244) {
///     print("Found: \(laterality.name)")
/// }
/// ```
public final class ContextGroupRegistry: @unchecked Sendable {
    /// The shared registry instance with well-known groups pre-registered
    public static let shared = ContextGroupRegistry()
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Internal storage by CID
    private var groups: [Int: ContextGroup] = [:]
    
    /// Creates an empty registry
    public init() {
        registerWellKnownGroups()
    }
    
    /// Register well-known context groups
    private func registerWellKnownGroups() {
        let wellKnown: [ContextGroup] = [
            .laterality,
            .measurementReportDocumentTitles,
            .relativeTime,
            .commonAnatomicRegion,
            .recistDefinedLesionResponse,
            .linearMeasurementUnit,
            .areaMeasurementUnit,
            .volumeMeasurementUnit,
            .breastImagingFinding,
            .measurementType
        ]
        
        for group in wellKnown {
            groups[group.cid] = group
        }
    }
    
    /// Look up a context group by its CID
    /// - Parameter cid: The Context Identifier number
    /// - Returns: The context group if found, nil otherwise
    public func group(forCID cid: Int) -> ContextGroup? {
        lock.lock()
        defer { lock.unlock() }
        return groups[cid]
    }
    
    /// Register a new context group
    /// - Parameter group: The context group to register
    public func register(_ group: ContextGroup) {
        lock.lock()
        defer { lock.unlock() }
        groups[group.cid] = group
    }
    
    /// Get all registered context groups
    /// - Returns: Array of all registered context groups
    public var allGroups: [ContextGroup] {
        lock.lock()
        defer { lock.unlock() }
        return Array(groups.values)
    }
    
    /// Validate a coded concept against a specific context group
    /// - Parameters:
    ///   - concept: The coded concept to validate
    ///   - cid: The Context Identifier number
    /// - Returns: ValidationResult, or nil if the CID is not registered
    public func validate(_ concept: CodedConcept, againstCID cid: Int) -> ContextGroup.ValidationResult? {
        lock.lock()
        defer { lock.unlock() }
        return groups[cid]?.validate(concept)
    }
}
