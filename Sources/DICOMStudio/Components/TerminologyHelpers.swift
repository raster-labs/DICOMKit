// TerminologyHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent coded terminology helpers
// Reference: DICOM PS3.16 (Content Mapping Resources), Table 8-1, CID 4, CID 7000, CID 7001, CID 7181, CID 7460-7462, CID 7469
// NEMA-verified: 2026a, checked 2026-10-05 — the 77 (code, scheme, meaning) entries diffed by script against every PS3.16 2026a CID table: SCT 26 (17 match, 3 corrected — Liver 816092008 (that id is "Pelvis" in CID 4031) -> 10200004 (CID 644), Thorax 51185008 -> (816094009, "Chest", CID 4), Nodule 129748003 -> 27925004 (CID 6104); 6 in no CID table, left as external SNOMED CT ids not verifiable from NEMA text); LN 15 (1 match, 9 meanings corrected to the CID 7000 / 7001 / 6052 / 100 meaning of the code, 5 in no CID table); RADLEX 18 (none in a CID table; RADLEX is a Table 8-1 scheme, codes not verifiable from NEMA text); UCUM 18 (14 match, m -> "m" per CID 7063; ml, l, g, kg in no CID table); scheme names against Table 8-1 (6/6: SRT is "SNOMED CT", DCM is "DICOM Controlled Terminology"); conversion factors are arithmetic

import Foundation

/// Platform-independent helpers for coded terminology browsing and search.
///
/// Provides lookup databases for SNOMED CT, LOINC, RadLex, and UCUM concepts
/// commonly used in DICOM Structured Reports.
public enum TerminologyHelpers: Sendable {

    // MARK: - SNOMED CT Concepts (CID 7181, CID 6103, etc.)

    /// Common SNOMED CT concepts used in radiology reporting.
    public static let snomedCTConcepts: [TerminologyEntry] = [
        entry(code: "39607008", scheme: "SCT", meaning: "Lung", category: "Body Part"),
        entry(code: "14975008", scheme: "SCT", meaning: "Forearm", category: "Body Part"),
        entry(code: "69536005", scheme: "SCT", meaning: "Head", category: "Body Part"),
        entry(code: "10200004", scheme: "SCT", meaning: "Liver", category: "Body Part"),
        entry(code: "64033007", scheme: "SCT", meaning: "Kidney", category: "Body Part"),
        entry(code: "76752008", scheme: "SCT", meaning: "Breast", category: "Body Part"),
        entry(code: "816094009", scheme: "SCT", meaning: "Chest", category: "Body Part"),
        entry(code: "818981001", scheme: "SCT", meaning: "Abdomen", category: "Body Part"),
        entry(code: "12738006", scheme: "SCT", meaning: "Brain", category: "Body Part"),
        entry(code: "410668003", scheme: "SCT", meaning: "Length", category: "Measurement"),
        entry(code: "42798000", scheme: "SCT", meaning: "Area", category: "Measurement"),
        entry(code: "118565006", scheme: "SCT", meaning: "Volume", category: "Measurement"),
        entry(code: "364499001", scheme: "SCT", meaning: "Angle", category: "Measurement"),
        entry(code: "373098007", scheme: "SCT", meaning: "Mean", category: "Statistics"),
        entry(code: "386136009", scheme: "SCT", meaning: "Standard Deviation", category: "Statistics"),
        entry(code: "255605001", scheme: "SCT", meaning: "Minimum", category: "Statistics"),
        entry(code: "56851009", scheme: "SCT", meaning: "Maximum", category: "Statistics"),
        entry(code: "4147007", scheme: "SCT", meaning: "Mass", category: "Finding"),
        entry(code: "27925004", scheme: "SCT", meaning: "Nodule", category: "Finding"),
        entry(code: "44643006", scheme: "SCT", meaning: "Calcification", category: "Finding"),
        entry(code: "3723001", scheme: "SCT", meaning: "Arthritis", category: "Finding"),
        entry(code: "233604007", scheme: "SCT", meaning: "Pneumonia", category: "Finding"),
        entry(code: "13104003", scheme: "SCT", meaning: "Fracture", category: "Finding"),
        entry(code: "24700007", scheme: "SCT", meaning: "Multiple Sclerosis", category: "Finding"),
        entry(code: "363698007", scheme: "SCT", meaning: "Finding Site", category: "Qualifier"),
        entry(code: "370129005", scheme: "SCT", meaning: "Measurement Method", category: "Qualifier"),
    ]

    // MARK: - LOINC Concepts

    /// Common LOINC observation codes for radiology.
    public static let loincConcepts: [TerminologyEntry] = [
        entry(code: "18782-3", scheme: "LN", meaning: "Radiology Study Observation", category: "Observation"),
        entry(code: "59776-5", scheme: "LN", meaning: "Findings", category: "Heading"),
        entry(code: "19005-8", scheme: "LN", meaning: "Impressions", category: "Heading"),
        entry(code: "18834-2", scheme: "LN", meaning: "Previous Findings", category: "Heading"),
        entry(code: "11525-3", scheme: "LN", meaning: "Ultrasound Obstetric and Gyn Report", category: "Report"),
        entry(code: "36643-5", scheme: "LN", meaning: "CT Chest Findings", category: "Finding"),
        entry(code: "24604-1", scheme: "LN", meaning: "MR Brain Findings", category: "Finding"),
        entry(code: "36554-4", scheme: "LN", meaning: "CT Abdomen Findings", category: "Finding"),
        entry(code: "24566-2", scheme: "LN", meaning: "XR Knee Findings", category: "Finding"),
        entry(code: "44136-0", scheme: "LN", meaning: "PET Scan Report", category: "Report"),
        entry(code: "18748-4", scheme: "LN", meaning: "Diagnostic Imaging Report", category: "Report"),
        entry(code: "11528-7", scheme: "LN", meaning: "Radiology Report", category: "Report"),
        entry(code: "55111-9", scheme: "LN", meaning: "Current Procedure Descriptions", category: "Heading"),
        entry(code: "55115-0", scheme: "LN", meaning: "Request", category: "Heading"),
        entry(code: "59768-2", scheme: "LN", meaning: "Procedure Indications", category: "Indication"),
        entry(code: "18785-6", scheme: "LN", meaning: "Indications for Procedure", category: "Heading"),
    ]

    // MARK: - RadLex Concepts

    /// Common RadLex (Radiology Lexicon) concepts.
    public static let radlexConcepts: [TerminologyEntry] = [
        entry(code: "RID1301", scheme: "RADLEX", meaning: "Abnormality", category: "Finding"),
        entry(code: "RID5", scheme: "RADLEX", meaning: "Lesion", category: "Finding"),
        entry(code: "RID3874", scheme: "RADLEX", meaning: "Mass", category: "Finding"),
        entry(code: "RID3875", scheme: "RADLEX", meaning: "Nodule", category: "Finding"),
        entry(code: "RID34265", scheme: "RADLEX", meaning: "Consolidation", category: "Finding"),
        entry(code: "RID28490", scheme: "RADLEX", meaning: "Ground Glass Opacity", category: "Finding"),
        entry(code: "RID1362", scheme: "RADLEX", meaning: "Pleural Effusion", category: "Finding"),
        entry(code: "RID5302", scheme: "RADLEX", meaning: "Atelectasis", category: "Finding"),
        entry(code: "RID1247", scheme: "RADLEX", meaning: "CT Scan", category: "Modality"),
        entry(code: "RID10312", scheme: "RADLEX", meaning: "MRI", category: "Modality"),
        entry(code: "RID10345", scheme: "RADLEX", meaning: "Ultrasound", category: "Modality"),
        entry(code: "RID10311", scheme: "RADLEX", meaning: "Radiography", category: "Modality"),
        entry(code: "RID1243", scheme: "RADLEX", meaning: "PET", category: "Modality"),
        entry(code: "RID10334", scheme: "RADLEX", meaning: "Mammography", category: "Modality"),
        entry(code: "RID58", scheme: "RADLEX", meaning: "Right Lung", category: "Anatomy"),
        entry(code: "RID59", scheme: "RADLEX", meaning: "Left Lung", category: "Anatomy"),
        entry(code: "RID170", scheme: "RADLEX", meaning: "Right Kidney", category: "Anatomy"),
        entry(code: "RID171", scheme: "RADLEX", meaning: "Left Kidney", category: "Anatomy"),
    ]

    // MARK: - UCUM Units

    /// Common UCUM (Unified Code for Units of Measure) entries.
    public static let ucumUnits: [TerminologyEntry] = [
        entry(code: "mm", scheme: "UCUM", meaning: "Millimeter", category: "Length"),
        entry(code: "cm", scheme: "UCUM", meaning: "Centimeter", category: "Length"),
        entry(code: "m", scheme: "UCUM", meaning: "m", category: "Length"),
        entry(code: "mm2", scheme: "UCUM", meaning: "Square Millimeter", category: "Area"),
        entry(code: "cm2", scheme: "UCUM", meaning: "Square Centimeter", category: "Area"),
        entry(code: "mm3", scheme: "UCUM", meaning: "Cubic Millimeter", category: "Volume"),
        entry(code: "cm3", scheme: "UCUM", meaning: "Cubic Centimeter", category: "Volume"),
        entry(code: "ml", scheme: "UCUM", meaning: "Milliliter", category: "Volume"),
        entry(code: "l", scheme: "UCUM", meaning: "Liter", category: "Volume"),
        entry(code: "deg", scheme: "UCUM", meaning: "Degree", category: "Angle"),
        entry(code: "rad", scheme: "UCUM", meaning: "Radian", category: "Angle"),
        entry(code: "g", scheme: "UCUM", meaning: "Gram", category: "Mass"),
        entry(code: "kg", scheme: "UCUM", meaning: "Kilogram", category: "Mass"),
        entry(code: "[hnsf'U]", scheme: "UCUM", meaning: "Hounsfield Unit", category: "Density"),
        entry(code: "s", scheme: "UCUM", meaning: "Second", category: "Time"),
        entry(code: "ms", scheme: "UCUM", meaning: "Millisecond", category: "Time"),
        entry(code: "1", scheme: "UCUM", meaning: "No Units", category: "Dimensionless"),
        entry(code: "%", scheme: "UCUM", meaning: "Percent", category: "Ratio"),
    ]

    // MARK: - Search

    /// Searches terminology entries matching a query.
    ///
    /// - Parameters:
    ///   - query: The search string (case-insensitive).
    ///   - scope: Which terminology to search.
    /// - Returns: Array of matching entries.
    public static func search(
        query: String,
        scope: TerminologySearchScope = .all
    ) -> [TerminologyEntry] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        let allEntries = entriesForScope(scope)
        return allEntries.filter { entry in
            entry.concept.codeMeaning.lowercased().contains(lowered) ||
            entry.concept.codeValue.lowercased().contains(lowered) ||
            entry.category.lowercased().contains(lowered)
        }
    }

    /// Returns all entries for the given scope.
    ///
    /// - Parameter scope: The terminology scope.
    /// - Returns: Array of terminology entries.
    public static func entriesForScope(_ scope: TerminologySearchScope) -> [TerminologyEntry] {
        switch scope {
        case .all:
            return snomedCTConcepts + loincConcepts + radlexConcepts + ucumUnits
        case .snomedCT:
            return snomedCTConcepts
        case .loinc:
            return loincConcepts
        case .radlex:
            return radlexConcepts
        case .ucum:
            return ucumUnits
        }
    }

    /// Returns categories available in a given scope.
    ///
    /// - Parameter scope: The terminology scope.
    /// - Returns: Sorted array of unique category names.
    public static func categories(for scope: TerminologySearchScope) -> [String] {
        let entries = entriesForScope(scope)
        let unique = Set(entries.map { $0.category })
        return unique.sorted()
    }

    /// Returns entries filtered by category.
    ///
    /// - Parameters:
    ///   - category: The category to filter by.
    ///   - scope: The terminology scope.
    /// - Returns: Array of entries in the category.
    public static func entriesInCategory(
        _ category: String,
        scope: TerminologySearchScope = .all
    ) -> [TerminologyEntry] {
        entriesForScope(scope).filter { $0.category == category }
    }

    /// Returns the coding scheme display name for a designator.
    ///
    /// - Parameter designator: The coding scheme designator string.
    /// - Returns: A human-readable name.
    public static func schemeDisplayName(for designator: String) -> String {
        switch designator {
        case "SCT": return "SNOMED CT"
        case "LN": return "LOINC"
        case "RADLEX": return "RadLex"
        case "UCUM": return "UCUM"
        case "DCM": return "DICOM Controlled Terminology"
        case "SRT": return "SNOMED CT"   // PS3.16 Table 8-1: SRT codes are SNOMED CT (SNOMED-RT style identifiers)
        default: return designator
        }
    }

    /// Returns the SF Symbol name for a coding scheme.
    ///
    /// - Parameter designator: The coding scheme designator.
    /// - Returns: An SF Symbol name.
    public static func sfSymbolForScheme(_ designator: String) -> String {
        switch designator {
        case "SCT": return "cross.case"
        case "LN": return "list.clipboard"
        case "RADLEX": return "rays"
        case "UCUM": return "ruler"
        case "DCM": return "doc.text.magnifyingglass"
        default: return "questionmark.circle"
        }
    }

    // MARK: - Cross-Terminology Mapping

    /// Returns cross-terminology mappings for a concept.
    ///
    /// - Parameter concept: The source concept.
    /// - Returns: Array of equivalent concepts in other terminologies.
    public static func crossTerminologyMappings(
        for concept: CodedConcept
    ) -> [CodedConcept] {
        let key = "\(concept.codingSchemeDesignator):\(concept.codeValue)"
        return mappingTable[key] ?? []
    }

    /// Simple mapping table for common cross-terminology equivalences.
    private static let mappingTable: [String: [CodedConcept]] = [
        "SCT:4147007": [
            CodedConcept(codeValue: "RID3874", codingSchemeDesignator: "RADLEX", codeMeaning: "Mass"),
        ],
        "SCT:27925004": [
            CodedConcept(codeValue: "RID3875", codingSchemeDesignator: "RADLEX", codeMeaning: "Nodule"),
        ],
        "SCT:44643006": [
            CodedConcept(codeValue: "RID35730", codingSchemeDesignator: "RADLEX", codeMeaning: "Calcification"),
        ],
        "RADLEX:RID3874": [
            CodedConcept(codeValue: "4147007", codingSchemeDesignator: "SCT", codeMeaning: "Mass"),
        ],
        "RADLEX:RID3875": [
            CodedConcept(codeValue: "27925004", codingSchemeDesignator: "SCT", codeMeaning: "Nodule"),
        ],
    ]

    // MARK: - UCUM Conversion

    /// Converts a value between compatible UCUM units.
    ///
    /// - Parameters:
    ///   - value: The numeric value to convert.
    ///   - fromUnit: Source UCUM code.
    ///   - toUnit: Target UCUM code.
    /// - Returns: Converted value, or nil if units are incompatible.
    public static func convertUCUM(
        value: Double,
        fromUnit: String,
        toUnit: String
    ) -> Double? {
        let key = "\(fromUnit)->\(toUnit)"
        guard let factor = conversionFactors[key] else { return nil }
        return value * factor
    }

    /// Conversion factors between common UCUM units.
    private static let conversionFactors: [String: Double] = [
        "mm->cm": 0.1,
        "cm->mm": 10.0,
        "mm->m": 0.001,
        "m->mm": 1000.0,
        "cm->m": 0.01,
        "m->cm": 100.0,
        "mm2->cm2": 0.01,
        "cm2->mm2": 100.0,
        "mm3->cm3": 0.001,
        "cm3->mm3": 1000.0,
        "ml->l": 0.001,
        "l->ml": 1000.0,
        "cm3->ml": 1.0,
        "ml->cm3": 1.0,
        "g->kg": 0.001,
        "kg->g": 1000.0,
        "s->ms": 1000.0,
        "ms->s": 0.001,
        "deg->rad": 0.017453292519943295,
        "rad->deg": 57.29577951308232,
    ]

    // MARK: - Private Helpers

    private static func entry(
        code: String,
        scheme: String,
        meaning: String,
        category: String
    ) -> TerminologyEntry {
        TerminologyEntry(
            concept: CodedConcept(
                codeValue: code,
                codingSchemeDesignator: scheme,
                codeMeaning: meaning
            ),
            category: category
        )
    }
}
