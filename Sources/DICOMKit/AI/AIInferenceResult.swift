// NEMA-verified: 2026a, checked 2026-09-29 — detection concepts against PS3.16 2026a CID 6104 / CID 7159 rows; anatomy constants against CID 4, CID 4030, CID 4031 rows; certainty against TID 4104 row 12 and CID 6048; legacy SRT codes against Table O-1; private scheme "99" prefix per PS3.16 Section 8 and PS3.3 Section 8.2
/// AI/ML Inference Result Integration
///
/// Provides protocols and types for converting AI/ML model outputs into DICOM Structured Reporting
/// documents. This enables seamless integration of machine learning detection and analysis results
/// with the DICOM ecosystem.
///
/// Reference: PS3.3 Section A.35 - CAD SR IODs
/// Reference: PS3.16 TID 4000 - CAD Analysis

import Foundation
import DICOMCore

// MARK: - Private Coding Scheme

/// The DICOMKit private coding scheme.
///
/// PS3.16 2026a Section 8 "Coding Schemes": "local or private Coding Schemes shall be identified by an
/// alphanumeric identifier beginning with the characters "99"" (as specified in HL7 v2 Table 0396).
/// PS3.3 2026a Section 8.2 allows such private designators "in accordance with PS3.16".
///
/// Codes from this scheme are only emitted for concepts for which PS3.16 2026a publishes no DCM or SCT
/// code (see the deprecated members of ``AIDetectionType`` and ``ConfidenceScore``). They are not
/// interoperable and receivers cannot be expected to understand them.
public enum DICOMKitPrivateCodingScheme {
    /// Coding Scheme Designator (0008,0102) of the DICOMKit private scheme
    public static let designator = "99DICOMKIT"

    /// Creates a coded concept in the DICOMKit private scheme
    /// - Parameters:
    ///   - codeValue: The private code value (SH, at most 16 characters)
    ///   - codeMeaning: The human-readable meaning
    public static func concept(_ codeValue: String, meaning codeMeaning: String) -> CodedConcept {
        CodedConcept(
            codeValue: codeValue,
            codingSchemeDesignator: designator,
            codeMeaning: codeMeaning
        )
    }
}

// MARK: - Core Protocol

/// Protocol for AI/ML inference results that can be converted to DICOM SR documents
///
/// Conforming types represent the output of AI/ML models and provide the necessary
/// information to create properly formatted DICOM Structured Report documents.
///
/// Example:
/// ```swift
/// struct MyDetectionResult: AIInferenceResult {
///     var modelName: String { "YOLOv8-Medical" }
///     var modelVersion: String { "1.2.3" }
///     var manufacturer: String { "My AI Company" }
///     var processingTimestamp: Date { Date() }
///     var detections: [AIDetection] { ... }
/// }
/// ```
public protocol AIInferenceResult: Sendable {
    /// Name of the AI/ML model that produced this result
    var modelName: String { get }

    /// Version of the AI/ML model
    var modelVersion: String { get }

    /// Manufacturer or developer of the model
    var manufacturer: String { get }

    /// Timestamp when the inference was performed
    var processingTimestamp: Date { get }

    /// Detected findings from the AI analysis
    var detections: [AIDetection] { get }

    /// Optional additional metadata about the inference
    var metadata: [String: String]? { get }
}

// MARK: - Default Implementation

extension AIInferenceResult {
    public var metadata: [String: String]? { nil }
}

// MARK: - Detection Types

/// Represents a single detection from an AI model
public struct AIDetection: Sendable, Equatable {
    /// Type of the detected finding
    public let type: AIDetectionType

    /// Confidence score (0.0 to 1.0)
    public let confidence: Double

    /// Spatial location of the detection
    public let location: AIDetectionLocation

    /// Optional characteristics or attributes
    public let attributes: [String: String]?

    /// Creates a new AI detection
    /// - Parameters:
    ///   - type: Type of detection
    ///   - confidence: Confidence score (0.0-1.0)
    ///   - location: Spatial location
    ///   - attributes: Optional key-value attributes
    public init(
        type: AIDetectionType,
        confidence: Double,
        location: AIDetectionLocation,
        attributes: [String: String]? = nil
    ) {
        self.type = type
        self.confidence = confidence
        self.location = location
        self.attributes = attributes
    }
}

/// Types of detections that AI models can produce
///
/// Every case with a fixed concept emits a code that appears in a PS3.16 2026a Context Group
/// (CID 6104 "Abnormal Opacity Finding or Feature" or CID 7159 "Lesion Segmentation Type").
/// Cases for which PS3.16 2026a publishes no concept are deprecated and emit a code from the
/// ``DICOMKitPrivateCodingScheme`` (`99DICOMKIT`); prefer ``custom(_:)`` with a code that is
/// meaningful in your report's context.
public enum AIDetectionType: Sendable, Equatable {
    // MARK: - Anatomical Findings

    /// Lung nodule detection — (27925004, SCT, "Nodule"), PS3.16 CID 6104
    case lungNodule

    /// Mass or tumor detection — (4147007, SCT, "Mass"), PS3.16 CID 6104
    case mass

    /// Calcification detection
    ///
    /// PS3.16 2026a has no general "Calcification" finding concept: Table D-1 and the CID tables only
    /// carry breast-specific concepts such as (309587003, SCT, "Calcification of breast") in CID 6054
    /// and (129769006, SCT, "Calcification Cluster") in CID 6015. ``concept`` therefore returns
    /// (CALCIFICATION, 99DICOMKIT, "Calcification").
    @available(*, deprecated, message: "PS3.16 2026a publishes no general \"Calcification\" concept (only breast-specific codes in CID 6015/6054); the concept is emitted from the private scheme 99DICOMKIT. Use .custom(_:) with a context-appropriate code.")
    case calcification

    /// Lesion detection (general) — (52988006, SCT, "Lesion"), PS3.16 CID 7159
    case lesion

    /// Fracture detection
    ///
    /// PS3.16 2026a has no "Fracture" finding concept: the only related CID row is
    /// (46866001, SCT, "Fracture of lower limb") in CID 3205, an indication for a stress test.
    /// ``concept`` therefore returns (FRACTURE, 99DICOMKIT, "Fracture").
    @available(*, deprecated, message: "PS3.16 2026a publishes no \"Fracture\" finding concept (CID 3205 only has \"Fracture of lower limb\"); the concept is emitted from the private scheme 99DICOMKIT. Use .custom(_:) with a context-appropriate code.")
    case fracture

    /// Hemorrhage detection — (50960005, SCT, "Hemorrhage"), PS3.16 CID 7159
    case hemorrhage

    /// Pneumonia or consolidation
    ///
    /// PS3.16 2026a has no "Pneumonia" or "Consolidation" concept in Table D-1 or any CID.
    /// ``concept`` therefore returns (PNEUMONIA, 99DICOMKIT, "Pneumonia").
    @available(*, deprecated, message: "PS3.16 2026a publishes no \"Pneumonia\" or \"Consolidation\" concept; the concept is emitted from the private scheme 99DICOMKIT. Use .custom(_:) with a context-appropriate code (CID 6104 lists opacity findings such as (112121, DCM, \"Infiltrate\")).")
    case pneumonia

    /// Pulmonary embolism — (59282003, SCT, "Pulmonary embolism"), PS3.16 CID 6104
    case pulmonaryEmbolism

    // MARK: - Organ/Structure Detection

    /// Anatomical structure (organ, vessel, etc.) identified by a real anatomy code
    ///
    /// Pass a concept from PS3.16 CID 4 "Anatomic Region" (which includes CID 4030 and CID 4031);
    /// ``AIAnatomicRegion`` provides verified constants. ``anatomicalStructure(_:)`` is the
    /// preferred constructor.
    case anatomy(CodedConcept)

    /// Anatomical structure (organ, vessel, etc.) identified by a real anatomy code
    ///
    /// Pass a concept from PS3.16 CID 4 "Anatomic Region" (which includes CID 4030 and CID 4031);
    /// ``AIAnatomicRegion`` provides verified constants. Equivalent to ``anatomy(_:)``.
    public static func anatomicalStructure(_ concept: CodedConcept) -> AIDetectionType {
        .anatomy(concept)
    }

    /// Anatomical structure identified only by a free-text name
    ///
    /// Formerly emitted (T-D0050, SRT) with the caller's name as the meaning; per PS3.16 2026a
    /// Table O-1, T-D0050 is (85756007, SCT, "Body tissue structure (body structure)") and does not
    /// identify any particular structure. ``concept`` now returns (ANATOMY, 99DICOMKIT, name).
    @available(*, deprecated, renamed: "anatomicalStructure(_:)", message: "(T-D0050, SRT) is \"Body tissue structure\" per PS3.16 2026a Table O-1, not a named structure; the concept is emitted from the private scheme 99DICOMKIT. Pass a CID 4 / CID 4030 / CID 4031 concept (see AIAnatomicRegion).")
    case anatomicalStructure(name: String)

    // MARK: - Custom Detection

    /// Custom detection type with coded concept
    case custom(CodedConcept)

    /// The coded concept representation for this detection type
    public var concept: CodedConcept {
        switch self {
        case .lungNodule:
            return CodedConcept(
                codeValue: "27925004",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Nodule"
            )
        case .mass:
            return CodedConcept(
                codeValue: "4147007",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Mass"
            )
        case .calcification:
            return DICOMKitPrivateCodingScheme.concept("CALCIFICATION", meaning: "Calcification")
        case .lesion:
            return CodedConcept(
                codeValue: "52988006",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Lesion"
            )
        case .fracture:
            return DICOMKitPrivateCodingScheme.concept("FRACTURE", meaning: "Fracture")
        case .hemorrhage:
            return CodedConcept(
                codeValue: "50960005",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Hemorrhage"
            )
        case .pneumonia:
            return DICOMKitPrivateCodingScheme.concept("PNEUMONIA", meaning: "Pneumonia")
        case .pulmonaryEmbolism:
            return CodedConcept(
                codeValue: "59282003",
                codingSchemeDesignator: "SCT",
                codeMeaning: "Pulmonary embolism"
            )
        case .anatomy(let concept):
            return concept
        case .anatomicalStructure(let name):
            return DICOMKitPrivateCodingScheme.concept("ANATOMY", meaning: name)
        case .custom(let concept):
            return concept
        }
    }
}

// MARK: - Anatomic Regions

/// Anatomy concepts for ``AIDetectionType/anatomicalStructure(_:)``.
///
/// Every constant is a row of PS3.16 2026a CID 4 "Anatomic Region", CID 4030 "CT, MR and PET Anatomy
/// Imaged" or CID 4031 "Common Anatomic Region" (CID 4 includes CID 4030, which includes CID 4031);
/// the source CID is named on each constant.
public enum AIAnatomicRegion {
    private static func sct(_ value: String, _ meaning: String) -> CodedConcept {
        CodedConcept(codeValue: value, codingSchemeDesignator: "SCT", codeMeaning: meaning)
    }

    // CID 4
    /// (39607008, SCT, "Lung") — CID 4
    public static let lung = sct("39607008", "Lung")
    /// (15497006, SCT, "Ovary") — CID 4
    public static let ovary = sct("15497006", "Ovary")

    // CID 4030
    /// (23451007, SCT, "Adrenal gland") — CID 4030
    public static let adrenalGland = sct("23451007", "Adrenal gland")
    /// (12738006, SCT, "Brain") — CID 4030
    public static let brain = sct("12738006", "Brain")
    /// (64033007, SCT, "Kidney") — CID 4030
    public static let kidney = sct("64033007", "Kidney")
    /// (10200004, SCT, "Liver") — CID 4030
    public static let liver = sct("10200004", "Liver")
    /// (78961009, SCT, "Spleen") — CID 4030
    public static let spleen = sct("78961009", "Spleen")
    /// (69748006, SCT, "Thyroid") — CID 4030
    public static let thyroid = sct("69748006", "Thyroid")
    /// (35039007, SCT, "Uterus") — CID 4030
    public static let uterus = sct("35039007", "Uterus")

    // CID 4031
    /// (818981001, SCT, "Abdomen") — CID 4031
    public static let abdomen = sct("818981001", "Abdomen")
    /// (818982008, SCT, "Abdomen and Pelvis") — CID 4031
    public static let abdomenAndPelvis = sct("818982008", "Abdomen and Pelvis")
    /// (89837001, SCT, "Bladder") — CID 4031
    public static let bladder = sct("89837001", "Bladder")
    /// (76752008, SCT, "Breast") — CID 4031
    public static let breast = sct("76752008", "Breast")
    /// (955009, SCT, "Bronchus") — CID 4031
    public static let bronchus = sct("955009", "Bronchus")
    /// (122494005, SCT, "Cervical spine") — CID 4031
    public static let cervicalSpine = sct("122494005", "Cervical spine")
    /// (816094009, SCT, "Chest") — CID 4 and CID 4031
    public static let chest = sct("816094009", "Chest")
    /// (71854001, SCT, "Colon") — CID 4031
    public static let colon = sct("71854001", "Colon")
    /// (32849002, SCT, "Esophagus") — CID 4031
    public static let esophagus = sct("32849002", "Esophagus")
    /// (71341001, SCT, "Femur") — CID 4031
    public static let femur = sct("71341001", "Femur")
    /// (56459004, SCT, "Foot") — CID 4031
    public static let foot = sct("56459004", "Foot")
    /// (28231008, SCT, "Gallbladder") — CID 4031
    public static let gallbladder = sct("28231008", "Gallbladder")
    /// (85562004, SCT, "Hand") — CID 4031
    public static let hand = sct("85562004", "Hand")
    /// (69536005, SCT, "Head") — CID 4031
    public static let head = sct("69536005", "Head")
    /// (80891009, SCT, "Heart") — CID 4031
    public static let heart = sct("80891009", "Heart")
    /// (29836001, SCT, "Hip") — CID 4031
    public static let hip = sct("29836001", "Hip")
    /// (85050009, SCT, "Humerus") — CID 4031
    public static let humerus = sct("85050009", "Humerus")
    /// (72696002, SCT, "Knee") — CID 4031
    public static let knee = sct("72696002", "Knee")
    /// (122496007, SCT, "Lumbar spine") — CID 4031
    public static let lumbarSpine = sct("122496007", "Lumbar spine")
    /// (72410000, SCT, "Mediastinum") — CID 4031
    public static let mediastinum = sct("72410000", "Mediastinum")
    /// (45048000, SCT, "Neck") — CID 4031
    public static let neck = sct("45048000", "Neck")
    /// (15776009, SCT, "Pancreas") — CID 4031
    public static let pancreas = sct("15776009", "Pancreas")
    /// (816092008, SCT, "Pelvis") — CID 4031
    public static let pelvis = sct("816092008", "Pelvis")
    /// (41216001, SCT, "Prostate") — CID 4031
    public static let prostate = sct("41216001", "Prostate")
    /// (113197003, SCT, "Rib") — CID 4031
    public static let rib = sct("113197003", "Rib")
    /// (16982005, SCT, "Shoulder") — CID 4031
    public static let shoulder = sct("16982005", "Shoulder")
    /// (89546000, SCT, "Skull") — CID 4031
    public static let skull = sct("89546000", "Skull")
    /// (421060004, SCT, "Spine") — CID 4031
    public static let spine = sct("421060004", "Spine")
    /// (69695003, SCT, "Stomach") — CID 4031
    public static let stomach = sct("69695003", "Stomach")
    /// (122495006, SCT, "Thoracic spine") — CID 4031
    public static let thoracicSpine = sct("122495006", "Thoracic spine")
    /// (44567001, SCT, "Trachea") — CID 4031
    public static let trachea = sct("44567001", "Trachea")
}

/// Spatial location of an AI detection
public enum AIDetectionLocation: Sendable, Equatable {
    // MARK: - 2D Locations

    /// Point location in 2D image space
    case point2D(x: Double, y: Double, imageReference: AIImageReference)

    /// Bounding box in 2D image space
    case boundingBox2D(x: Double, y: Double, width: Double, height: Double, imageReference: AIImageReference)

    /// Polygon region in 2D image space
    case polygon2D(points: [Double], imageReference: AIImageReference)

    /// Circle in 2D image space
    case circle2D(centerX: Double, centerY: Double, radius: Double, imageReference: AIImageReference)

    // MARK: - 3D Locations

    /// Point location in 3D patient coordinate space
    case point3D(x: Double, y: Double, z: Double, frameOfReferenceUID: String, imageReference: AIImageReference?)

    /// Bounding box in 3D patient coordinate space
    case boundingBox3D(
        x: Double, y: Double, z: Double,
        width: Double, height: Double, depth: Double,
        frameOfReferenceUID: String,
        imageReference: AIImageReference?
    )

    /// Polygon in 3D patient coordinate space
    case polygon3D(points: [Double], frameOfReferenceUID: String, imageReference: AIImageReference?)

    /// Ellipsoid in 3D patient coordinate space
    case ellipsoid3D(
        centerX: Double, centerY: Double, centerZ: Double,
        radiusX: Double, radiusY: Double, radiusZ: Double,
        frameOfReferenceUID: String,
        imageReference: AIImageReference?
    )
}

/// Reference to a DICOM image that the detection relates to
public struct AIImageReference: Sendable, Equatable {
    /// SOP Class UID of the referenced image
    public let sopClassUID: String

    /// SOP Instance UID of the referenced image
    public let sopInstanceUID: String

    /// Optional frame number for multi-frame images (1-based)
    public let frameNumber: Int?

    /// Creates a new image reference
    /// - Parameters:
    ///   - sopClassUID: SOP Class UID
    ///   - sopInstanceUID: SOP Instance UID
    ///   - frameNumber: Optional frame number (1-based)
    public init(sopClassUID: String, sopInstanceUID: String, frameNumber: Int? = nil) {
        self.sopClassUID = sopClassUID
        self.sopInstanceUID = sopInstanceUID
        self.frameNumber = frameNumber
    }
}

// MARK: - Confidence Score Utilities

/// Utilities for encoding and interpreting AI confidence scores
///
/// The standard way to convey a detector's confidence in an SR is a NUM content item
/// (111012, DCM, "Certainty of Finding") with units (%, UCUM, "Percent") and a value of 0-100,
/// related to the finding by HAS PROPERTIES: PS3.16 2026a TID 4104 "Chest CAD Single Image Finding"
/// row 12, TID 4006 row 6 and TID 4127 row 8. Use ``certaintyOfFinding(_:relationshipType:)``.
public enum ConfidenceScore {
    /// (111012, DCM, "Certainty of Finding") — PS3.16 2026a Table D-1 and CID 6048; the concept name
    /// of the certainty NUM in TID 4104 row 12
    public static let certaintyOfFindingConcept = CodedConcept(
        codeValue: "111012",
        codingSchemeDesignator: "DCM",
        codeMeaning: "Certainty of Finding"
    )

    /// (%, UCUM, "Percent") — the units required by PS3.16 2026a TID 4104 row 12
    public static let percentUnits = CodedConcept(
        codeValue: "%",
        codingSchemeDesignator: "UCUM",
        codeMeaning: "Percent"
    )

    /// Converts a 0.0-1.0 confidence score to a percentage string
    /// - Parameter score: Confidence score (0.0-1.0)
    /// - Returns: Percentage string (e.g., "85.5")
    public static func toPercentageString(_ score: Double) -> String {
        let percentage = score * 100.0
        return String(format: "%.1f", percentage)
    }

    /// Converts a 0.0-1.0 confidence score to a percentage in 0-100
    /// - Parameter score: Confidence score (0.0-1.0); values outside the range are clamped
    /// - Returns: Percentage (0-100)
    public static func toPercent(_ score: Double) -> Double {
        min(max(score, 0.0), 1.0) * 100.0
    }

    /// Encodes a 0.0-1.0 confidence score as the standard certainty NUM content item
    ///
    /// PS3.16 2026a TID 4104 row 12: NUM, EV (111012, DCM, "Certainty of Finding"),
    /// UNITS = EV (%, UCUM, "Percent"), Value = 0 - 100, relationship HAS PROPERTIES.
    /// - Parameters:
    ///   - score: Confidence score (0.0-1.0); values outside the range are clamped
    ///   - relationshipType: Relationship to the finding (default HAS PROPERTIES per TID 4104)
    /// - Returns: The NUM content item
    public static func certaintyOfFinding(
        _ score: Double,
        relationshipType: RelationshipType? = .hasProperties
    ) -> NumericContentItem {
        NumericContentItem(
            conceptName: certaintyOfFindingConcept,
            value: toPercent(score),
            units: percentUnits,
            relationshipType: relationshipType
        )
    }

    /// Converts a 0.0-1.0 confidence score to a categorical coded concept
    ///
    /// The codes formerly emitted, R-00339/R-00340/R-00341 (SRT), are per PS3.16 2026a Table O-1
    /// (373067005, SCT, "No (qualifier value)"), (371857005, SCT, "Normal left ventricular systolic
    /// function and wall motion (finding)") and (373129009, SCT, "Normal overall cardiac contractility
    /// (finding)"): they never meant a confidence level. PS3.16 2026a defines no categorical confidence
    /// concept, so this returns a ``DICOMKitPrivateCodingScheme`` code
    /// (CONF_HIGH / CONF_MEDIUM / CONF_LOW, 99DICOMKIT).
    /// - Parameter score: Confidence score (0.0-1.0)
    /// - Returns: Private coded concept representing the confidence category
    @available(*, deprecated, renamed: "certaintyOfFinding(_:relationshipType:)", message: "PS3.16 2026a has no categorical confidence concept (R-00339/R-00340/R-00341 mean other things per Table O-1); this now emits a 99DICOMKIT private code. Emit a NUM (111012, DCM, \"Certainty of Finding\") in % per TID 4104 row 12 instead.")
    public static func toCodedConcept(_ score: Double) -> CodedConcept {
        categorize(score).privateConcept
    }

    /// Categorizes a confidence score
    /// - Parameter score: Confidence score (0.0-1.0)
    /// - Returns: Confidence category
    public static func categorize(_ score: Double) -> ConfidenceCategory {
        switch score {
        case 0.9...1.0:
            return .high
        case 0.7..<0.9:
            return .medium
        default:
            return .low
        }
    }
}

/// Confidence score categories
public enum ConfidenceCategory: String, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    /// The category as a ``DICOMKitPrivateCodingScheme`` concept
    ///
    /// PS3.16 2026a publishes no categorical confidence concept; the standard representation is the
    /// numeric ``ConfidenceScore/certaintyOfFinding(_:relationshipType:)``.
    public var privateConcept: CodedConcept {
        switch self {
        case .high:
            return DICOMKitPrivateCodingScheme.concept("CONF_HIGH", meaning: "High confidence")
        case .medium:
            return DICOMKitPrivateCodingScheme.concept("CONF_MEDIUM", meaning: "Medium confidence")
        case .low:
            return DICOMKitPrivateCodingScheme.concept("CONF_LOW", meaning: "Low confidence")
        }
    }
}
