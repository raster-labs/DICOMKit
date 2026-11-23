// TerminologyHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent coded terminology helpers
// Reference: DICOM PS3.16 (Content Mapping Resources), Table 8-1, CID 4, CID 7000, CID 7001, CID 7181, CID 7460-7462, CID 7469
// NEMA-verified: 2026a, checked 2026-10-05 — the 77 (code, scheme, meaning) entries diffed by script against every PS3.16 2026a CID table: SCT 26 (17 match, 3 corrected — Liver 816092008 (that id is "Pelvis" in CID 4031) -> 10200004 (CID 644), Thorax 51185008 -> (816094009, "Chest", CID 4), Nodule 129748003 -> 27925004 (CID 6104); 6 in no CID table, left as external SNOMED CT ids not verifiable from NEMA text); LN 15 (1 match, 9 meanings corrected to the CID 7000 / 7001 / 6052 / 100 meaning of the code, 5 in no CID table); RADLEX 18 (none in a CID table; RADLEX is a Table 8-1 scheme, codes not verifiable from NEMA text); UCUM 18 (14 match, m -> "m" per CID 7063; ml, l, g, kg in no CID table); scheme names against Table 8-1 (6/6: SRT is "SNOMED CT", DCM is "DICOM Controlled Terminology"); conversion factors are arithmetic

import Foundation
import DICOMCore

/// Platform-independent helpers for coded terminology browsing and search.
///
/// Delegates all SNOMED CT, LOINC, RadLex, and UCUM concept databases, scheme display names,
/// cross-terminology mappings, and UCUM conversions directly to `DICOMCore.SRTerminologyCatalog`.
public enum TerminologyHelpers: Sendable {

    // MARK: - Terminology Databases (Delegated to DICOMCore.SRTerminologyCatalog)

    /// Common SNOMED CT concepts used in radiology reporting, sourced from `DICOMCore.SRTerminologyCatalog`.
    public static let snomedCTConcepts: [TerminologyEntry] =
        DICOMCore.SRTerminologyCatalog.snomedCTEntries.map(fromCatalogEntry)

    /// Common LOINC observation codes for radiology, sourced from `DICOMCore.SRTerminologyCatalog`.
    public static let loincConcepts: [TerminologyEntry] =
        DICOMCore.SRTerminologyCatalog.loincEntries.map(fromCatalogEntry)

    /// Common RadLex (Radiology Lexicon) concepts, sourced from `DICOMCore.SRTerminologyCatalog`.
    public static let radlexConcepts: [TerminologyEntry] =
        DICOMCore.SRTerminologyCatalog.radlexEntries.map(fromCatalogEntry)

    /// Common UCUM (Unified Code for Units of Measure) entries, sourced from `DICOMCore.SRTerminologyCatalog`.
    public static let ucumUnits: [TerminologyEntry] =
        DICOMCore.SRTerminologyCatalog.ucumEntries.map(fromCatalogEntry)

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

    /// Returns the coding scheme display name for a designator, delegated to `DICOMCore.SRTerminologyCatalog`.
    ///
    /// - Parameter designator: The coding scheme designator string.
    /// - Returns: A human-readable name.
    public static func schemeDisplayName(for designator: String) -> String {
        DICOMCore.SRTerminologyCatalog.schemeDisplayName(for: designator)
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

    /// Returns cross-terminology mappings for a concept, delegated to `DICOMCore.SRTerminologyCatalog`.
    ///
    /// - Parameter concept: The source concept.
    /// - Returns: Array of equivalent concepts in other terminologies.
    public static func crossTerminologyMappings(
        for concept: CodedConcept
    ) -> [CodedConcept] {
        DICOMCore.SRTerminologyCatalog.crossTerminologyMappings(for: concept.coreConcept)
            .map { CodedConcept(coreConcept: $0) }
    }

    // MARK: - UCUM Conversion

    /// Converts a value between compatible UCUM units, delegated to `DICOMCore.SRTerminologyCatalog`.
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
        DICOMCore.SRTerminologyCatalog.convertUCUM(
            value: value,
            fromUnit: fromUnit,
            toUnit: toUnit
        )
    }

    // MARK: - Private Helpers

    private static func fromCatalogEntry(_ catalogEntry: DICOMCore.SRTerminologyCatalog.CatalogEntry) -> TerminologyEntry {
        TerminologyEntry(
            concept: CodedConcept(coreConcept: catalogEntry.concept),
            category: catalogEntry.category
        )
    }
}
