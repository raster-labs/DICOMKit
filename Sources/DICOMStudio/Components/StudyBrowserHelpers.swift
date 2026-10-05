// StudyBrowserHelpers.swift
// DICOMStudio
//
// DICOM Studio — Platform-independent helpers for study browser logic
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (sorting, filtering and search over the
// library models).

import Foundation

/// Platform-independent helpers for study browser sorting, filtering, and searching.
///
/// These helpers are separated from SwiftUI views to enable testing on all platforms,
/// including Linux CI where SwiftUI is not available.
public enum StudyBrowserHelpers: Sendable {

    /// Filters studies by the given filter criteria.
    ///
    /// - Parameters:
    ///   - studies: The studies to filter.
    ///   - filter: The filter criteria.
    /// - Returns: Filtered array of studies.
    public static func filter(
        studies: [StudyModel],
        with filter: LibraryFilter
    ) -> [StudyModel] {
        guard filter.isActive else { return studies }

        return studies.filter { study in
            // Modality filter
            if !filter.modalities.isEmpty {
                let studyModalities = study.modalitiesInStudy
                if studyModalities.isDisjoint(with: filter.modalities) {
                    return false
                }
            }

            // Date range filter
            if let from = filter.dateFrom, let studyDate = study.studyDate {
                if studyDate < from { return false }
            }
            if let to = filter.dateTo, let studyDate = study.studyDate {
                if studyDate > to { return false }
            }

            // Patient name filter
            if !filter.patientName.isEmpty {
                let name = study.patientName ?? ""
                if !name.localizedCaseInsensitiveContains(filter.patientName) {
                    return false
                }
            }

            // Full-text search
            if !filter.searchText.isEmpty {
                if !matchesSearch(study: study, text: filter.searchText) {
                    return false
                }
            }

            return true
        }
    }

    /// Sorts studies by the given field and direction.
    ///
    /// - Parameters:
    ///   - studies: The studies to sort.
    ///   - field: The sort field.
    ///   - direction: The sort direction.
    /// - Returns: Sorted array of studies.
    public static func sort(
        studies: [StudyModel],
        by field: StudySortField,
        direction: SortDirection
    ) -> [StudyModel] {
        let sorted = studies.sorted { lhs, rhs in
            let result: Bool
            switch field {
            case .date:
                result = compareDates(lhs.studyDate, rhs.studyDate)
            case .patientName:
                result = compareStrings(lhs.patientName, rhs.patientName)
            case .modality:
                result = compareStrings(lhs.displayModalities, rhs.displayModalities)
            case .studyDescription:
                result = compareStrings(lhs.studyDescription, rhs.studyDescription)
            }
            return direction == .ascending ? result : !result
        }
        return sorted
    }

    /// Checks if a study matches a full-text search query.
    ///
    /// Searches across patient name, patient ID, study description,
    /// accession number, referring physician, institution name, and modalities.
    ///
    /// - Parameters:
    ///   - study: The study to check.
    ///   - text: The search text.
    /// - Returns: `true` if any field contains the search text.
    public static func matchesSearch(study: StudyModel, text: String) -> Bool {
        let searchableFields: [String?] = [
            study.patientName,
            study.patientID,
            study.studyDescription,
            study.accessionNumber,
            study.referringPhysicianName,
            study.institutionName,
            study.studyID,
            study.displayModalities
        ]

        return searchableFields.contains { field in
            guard let field = field, !field.isEmpty else { return false }
            return field.localizedCaseInsensitiveContains(text)
        }
    }

    /// Returns a count badge string for study/series/instance counts.
    ///
    /// - Parameters:
    ///   - series: Number of series.
    ///   - instances: Number of instances.
    /// - Returns: Formatted badge string like "3 series · 120 images".
    public static func countBadge(series: Int, instances: Int) -> String {
        let seriesText = series == 1 ? "1 series" : "\(series) series"
        let instanceText = instances == 1 ? "1 image" : "\(instances) images"
        return "\(seriesText) · \(instanceText)"
    }

    /// Returns unique modalities from a collection of studies.
    ///
    /// - Parameter studies: The studies to extract modalities from.
    /// - Returns: Sorted array of unique modality codes.
    public static func uniqueModalities(in studies: [StudyModel]) -> [String] {
        var modalities = Set<String>()
        for study in studies {
            modalities.formUnion(study.modalitiesInStudy)
        }
        return modalities.sorted()
    }

    // MARK: - Private Comparison Helpers

    private static func compareDates(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (l?, r?): return l < r
        case (nil, _?): return true
        case (_?, nil): return false
        case (nil, nil): return false
        }
    }

    private static func compareStrings(_ lhs: String?, _ rhs: String?) -> Bool {
        let l = lhs ?? ""
        let r = rhs ?? ""
        return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
    }
}
