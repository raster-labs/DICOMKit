/// LOINCCode - Logical Observation Identifiers Names and Codes support
///
/// Provides specialized types and common codes for LOINC, the international
/// standard for identifying health measurements, observations, and documents.
///
/// Reference: PS3.16 - Content Mapping Resource
/// Reference: LOINC.org - https://loinc.org/
///
/// NEMA-verified: 2026a, checked 2026-09-25 — LOINC is outside NEMA's scope; the check was against every LN code used in PS3.16 2026a context groups. Of 53 constants, 17 appear in PS3.16: 5 with the same meaning, 12 with a different Code Meaning (mostly PS3.16 wording such as "Impressions" vs "Impression"), and 36 do not appear at all and were not verified. Four names were wrong LOINC concepts and were corrected on 2026-09-25: 18748-4 is "Diagnostic imaging study" (was "Radiology Report"), 55111-9 "Current imaging procedure descriptions" (was "Technique"), 24590-2 "MR Brain" (was "MRI report"), 18750-0 "Cardiac electrophysiology study" (was "Ultrasound report"); callers wanting an ultrasound or generic MRI report concept should pick another code.

/// A LOINC code with associated metadata
///
/// LOINC codes are alphanumeric identifiers that represent clinical observations,
/// laboratory tests, and document types. This type provides a type-safe way
/// to work with LOINC concepts.
///
/// Example:
/// ```swift
/// let bodyWeight = LOINCCode.bodyWeight
/// print(bodyWeight.concept.description) // "(29463-7, LN, "Body weight")"
/// ```
public struct LOINCCode: Sendable, Equatable, Hashable {
    /// The coded concept representation
    public let concept: CodedConcept
    
    /// The LOINC code number
    public var loincNum: String { concept.codeValue }
    
    /// The LOINC long common name
    public var longCommonName: String { concept.codeMeaning }
    
    /// Creates a LOINC code from a code number and display name
    /// - Parameters:
    ///   - loincNum: The LOINC number (e.g., "29463-7")
    ///   - longCommonName: The long common name
    public init(loincNum: String, longCommonName: String) {
        self.concept = CodedConcept(
            codeValue: loincNum,
            scheme: .LOINC,
            codeMeaning: longCommonName
        )
    }
    
    /// Creates a LOINC code from an existing CodedConcept
    /// - Parameter concept: A coded concept using LN designator
    /// - Returns: nil if the concept is not a LOINC code
    public init?(concept: CodedConcept) {
        guard concept.codingSchemeDesignator == CodingSchemeDesignator.LOINC.rawValue else {
            return nil
        }
        self.concept = concept
    }
}

// MARK: - CustomStringConvertible

extension LOINCCode: CustomStringConvertible {
    public var description: String {
        concept.description
    }
}

// MARK: - Common Observation Codes

extension LOINCCode {
    // MARK: - Vital Signs
    
    /// Body weight (29463-7)
    public static let bodyWeight = LOINCCode(loincNum: "29463-7", longCommonName: "Body weight")
    
    /// Body height (8302-2)
    public static let bodyHeight = LOINCCode(loincNum: "8302-2", longCommonName: "Body height")
    
    /// Body mass index (39156-5)
    public static let bodyMassIndex = LOINCCode(loincNum: "39156-5", longCommonName: "Body mass index")
    
    /// Body temperature (8310-5)
    public static let bodyTemperature = LOINCCode(loincNum: "8310-5", longCommonName: "Body temperature")
    
    /// Heart rate (8867-4)
    public static let heartRate = LOINCCode(loincNum: "8867-4", longCommonName: "Heart rate")
    
    /// Respiratory rate (9279-1)
    public static let respiratoryRate = LOINCCode(loincNum: "9279-1", longCommonName: "Respiratory rate")
    
    /// Systolic blood pressure (8480-6)
    public static let systolicBloodPressure = LOINCCode(loincNum: "8480-6", longCommonName: "Systolic blood pressure")
    
    /// Diastolic blood pressure (8462-4)
    public static let diastolicBloodPressure = LOINCCode(loincNum: "8462-4", longCommonName: "Diastolic blood pressure")
    
    /// Oxygen saturation (2708-6)
    public static let oxygenSaturation = LOINCCode(loincNum: "2708-6", longCommonName: "Oxygen saturation")
}

// MARK: - Measurement Type Codes

extension LOINCCode {
    // MARK: - Length/Distance Measurements
    
    /// Diameter (33728-7)
    public static let diameter = LOINCCode(loincNum: "33728-7", longCommonName: "Diameter")
    
    /// Length (8302-2)
    public static let length = LOINCCode(loincNum: "18688-2", longCommonName: "Length")
    
    /// Width (81190-8)
    public static let width = LOINCCode(loincNum: "81190-8", longCommonName: "Width")
    
    /// Depth (81191-6)
    public static let depth = LOINCCode(loincNum: "81191-6", longCommonName: "Depth")
    
    // MARK: - Area/Volume Measurements
    
    /// Area (81298-9)
    public static let area = LOINCCode(loincNum: "81298-9", longCommonName: "Area")
    
    /// Volume (81297-1)
    public static let volume = LOINCCode(loincNum: "81297-1", longCommonName: "Volume")
    
    // MARK: - Density/Attenuation
    
    /// Mean density (89221-2)
    public static let meanDensity = LOINCCode(loincNum: "89221-2", longCommonName: "Mean density")
    
    /// Maximum density (89222-0)
    public static let maxDensity = LOINCCode(loincNum: "89222-0", longCommonName: "Maximum density")
    
    /// Minimum density (89223-8)
    public static let minDensity = LOINCCode(loincNum: "89223-8", longCommonName: "Minimum density")
    
    /// Standard deviation of density (89224-6)
    public static let stdDevDensity = LOINCCode(loincNum: "89224-6", longCommonName: "Standard deviation of density")
    
    // MARK: - Signal Intensity (MRI)
    
    /// Mean signal intensity (89225-3)
    public static let meanSignalIntensity = LOINCCode(loincNum: "89225-3", longCommonName: "Mean signal intensity")
    
    /// Maximum signal intensity (89226-1)
    public static let maxSignalIntensity = LOINCCode(loincNum: "89226-1", longCommonName: "Maximum signal intensity")
    
    // MARK: - Other Measurements
    
    /// Circumference (8280-0)
    public static let circumference = LOINCCode(loincNum: "8280-0", longCommonName: "Circumference")
    
    /// Angle (81294-8)
    public static let angle = LOINCCode(loincNum: "81294-8", longCommonName: "Angle")
}

// MARK: - Radiology Report Section Codes

extension LOINCCode {
    // MARK: - Report Sections
    
    /// Radiology report (18748-4)
    public static let radiologyReport = LOINCCode(loincNum: "18748-4", longCommonName: "Diagnostic imaging study")
    
    /// Clinical information (55752-0)
    public static let clinicalInformation = LOINCCode(loincNum: "55752-0", longCommonName: "Clinical information")
    
    /// History of present illness (10164-2)
    public static let historyOfPresentIllness = LOINCCode(loincNum: "10164-2", longCommonName: "History of present illness")
    
    /// Reason for study (18785-6)
    public static let reasonForStudy = LOINCCode(loincNum: "18785-6", longCommonName: "Reason for study")
    
    /// Comparison study (18834-2)
    public static let comparisonStudy = LOINCCode(loincNum: "18834-2", longCommonName: "Comparison study")
    
    /// Technique (55111-9)
    public static let technique = LOINCCode(loincNum: "55111-9", longCommonName: "Current imaging procedure descriptions")
    
    /// Findings (59776-5)
    public static let findings = LOINCCode(loincNum: "59776-5", longCommonName: "Findings")
    
    /// Impression (19005-8)
    public static let impression = LOINCCode(loincNum: "19005-8", longCommonName: "Impression")
    
    /// Recommendation (18783-1)
    public static let recommendation = LOINCCode(loincNum: "18783-1", longCommonName: "Recommendation")
    
    /// Procedure description (29554-3)
    public static let procedureDescription = LOINCCode(loincNum: "29554-3", longCommonName: "Procedure description")
    
    /// Conclusion (55110-1)
    public static let conclusion = LOINCCode(loincNum: "55110-1", longCommonName: "Conclusion")
    
    /// Summary (55112-7)
    public static let summary = LOINCCode(loincNum: "55112-7", longCommonName: "Summary")
    
    // MARK: - Specific Report Types
    
    /// CT scan report (24727-0)
    public static let ctScanReport = LOINCCode(loincNum: "24727-0", longCommonName: "CT scan report")
    
    /// MRI report (24590-2)
    public static let mriReport = LOINCCode(loincNum: "24590-2", longCommonName: "MR Brain")
    
    /// Mammography report (24605-8)
    public static let mammographyReport = LOINCCode(loincNum: "24605-8", longCommonName: "Mammography report")
    
    /// Ultrasound report (18750-0)
    public static let ultrasoundReport = LOINCCode(loincNum: "18750-0", longCommonName: "Cardiac electrophysiology study")
    
    /// Nuclear medicine report (18747-6)
    public static let nuclearMedicineReport = LOINCCode(loincNum: "18747-6", longCommonName: "Nuclear medicine report")
    
    /// PET scan report (44136-0)
    public static let petScanReport = LOINCCode(loincNum: "44136-0", longCommonName: "PET scan report")
    
    /// Chest X-ray report (30746-2)
    public static let chestXRayReport = LOINCCode(loincNum: "30746-2", longCommonName: "Chest X-ray report")
    
    /// Interventional radiology report (75496-0)
    public static let interventionalRadiologyReport = LOINCCode(loincNum: "75496-0", longCommonName: "Interventional radiology report")
}

// MARK: - Document Types

extension LOINCCode {
    /// Diagnostic imaging study (18726-0)
    public static let diagnosticImagingStudy = LOINCCode(loincNum: "18726-0", longCommonName: "Diagnostic imaging study")
    
    /// Procedure note (28570-0)
    public static let procedureNote = LOINCCode(loincNum: "28570-0", longCommonName: "Procedure note")
    
    /// Consultation note (11488-4)
    public static let consultationNote = LOINCCode(loincNum: "11488-4", longCommonName: "Consultation note")
    
    /// Discharge summary (18842-5)
    public static let dischargeSummary = LOINCCode(loincNum: "18842-5", longCommonName: "Discharge summary")
    
    /// Progress note (11506-3)
    public static let progressNote = LOINCCode(loincNum: "11506-3", longCommonName: "Progress note")
}

// MARK: - Laboratory Panel Codes

extension LOINCCode {
    /// Complete blood count (CBC) (58410-2)
    public static let completeBloodCount = LOINCCode(loincNum: "58410-2", longCommonName: "Complete blood count panel")
    
    /// Comprehensive metabolic panel (24323-8)
    public static let comprehensiveMetabolicPanel = LOINCCode(loincNum: "24323-8", longCommonName: "Comprehensive metabolic panel")
    
    /// Lipid panel (57698-3)
    public static let lipidPanel = LOINCCode(loincNum: "57698-3", longCommonName: "Lipid panel")
    
    /// Liver function tests (24325-3)
    public static let liverFunctionTests = LOINCCode(loincNum: "24325-3", longCommonName: "Liver function tests panel")
    
    /// Thyroid panel (34430-3)
    public static let thyroidPanel = LOINCCode(loincNum: "34430-3", longCommonName: "Thyroid panel")
}

// MARK: - CodedConcept Convenience

extension CodedConcept {
    /// Create a CodedConcept from a LOINCCode
    /// - Parameter loinc: The LOINC code
    /// - Returns: A coded concept with LN designator
    public init(loinc: LOINCCode) {
        self = loinc.concept
    }
    
    /// Attempt to convert this coded concept to a LOINCCode
    /// - Returns: A LOINCCode if this is a LOINC concept, nil otherwise
    public var asLOINC: LOINCCode? {
        LOINCCode(concept: self)
    }
    
    /// Returns whether this concept uses LOINC coding scheme
    public var isLOINC: Bool {
        codingSchemeDesignator == CodingSchemeDesignator.LOINC.rawValue
    }
}
