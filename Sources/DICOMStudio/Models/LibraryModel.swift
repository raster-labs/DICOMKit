// LibraryModel.swift
// DICOMStudio
//
// DICOM Studio — Local file database model
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (in-memory study/series/instance index
// keyed by the UIDs).

import Foundation

/// Manages the local DICOM file library, providing study/series/instance organization.
///
/// The library maintains an in-memory index of imported DICOM files,
/// organized by the standard DICOM study–series–instance hierarchy.
public struct LibraryModel: Sendable {
    /// All studies in the library, keyed by Study Instance UID.
    public private(set) var studies: [String: StudyModel]

    /// All series in the library, keyed by Series Instance UID.
    public private(set) var series: [String: SeriesModel]

    /// All instances in the library, keyed by SOP Instance UID.
    public private(set) var instances: [String: InstanceModel]

    /// Mapping from Study Instance UID to its Series Instance UIDs.
    public private(set) var studySeries: [String: Set<String>]

    /// Mapping from Series Instance UID to its SOP Instance UIDs.
    public private(set) var seriesInstances: [String: Set<String>]

    /// Creates an empty library.
    public init() {
        self.studies = [:]
        self.series = [:]
        self.instances = [:]
        self.studySeries = [:]
        self.seriesInstances = [:]
    }

    /// Returns all studies sorted by study date (most recent first).
    public var sortedStudies: [StudyModel] {
        studies.values.sorted { lhs, rhs in
            switch (lhs.studyDate, rhs.studyDate) {
            case let (l?, r?): return l > r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.studyInstanceUID < rhs.studyInstanceUID
            }
        }
    }

    /// Returns the series of a study in Series Number order.
    ///
    /// Ascending, with unnumbered series last — a missing number is not series
    /// zero — and Series UID breaking ties, so a study lists its series the same
    /// way every time it is opened.
    public func seriesForStudy(_ studyUID: String) -> [SeriesModel] {
        guard let seriesUIDs = studySeries[studyUID] else { return [] }
        return seriesUIDs.compactMap { series[$0] }.sorted { lhs, rhs in
            let left = lhs.seriesNumber ?? Int.max
            let right = rhs.seriesNumber ?? Int.max
            if left != right { return left < right }
            return lhs.seriesInstanceUID < rhs.seriesInstanceUID
        }
    }

    /// Returns the instances for a given series, in Instance Number order.
    ///
    /// Instance Number (0020,0013) is the order the images were acquired in,
    /// which is the order a stack is read in — so it decides which image a
    /// series opens on and which way the arrow keys walk.
    ///
    /// Unnumbered instances sort last rather than first (a missing number is
    /// not instance zero), and file path breaks every tie: instances come out of
    /// an unordered set, so without a total order a series with duplicate or
    /// absent numbers would arrange itself differently on each read — and open
    /// on a different image each time.
    public func instancesForSeries(_ seriesUID: String) -> [InstanceModel] {
        guard let instanceUIDs = seriesInstances[seriesUID] else { return [] }
        return instanceUIDs.compactMap { instances[$0] }.sorted { lhs, rhs in
            let left = lhs.instanceNumber ?? Int.max
            let right = rhs.instanceNumber ?? Int.max
            if left != right { return left < right }
            return lhs.filePath < rhs.filePath
        }
    }

    /// Number of instances across every series of a study.
    public func instanceCount(forStudy studyUID: String) -> Int {
        seriesForStudy(studyUID).reduce(0) {
            $0 + (seriesInstances[$1.seriesInstanceUID]?.count ?? 0)
        }
    }

    /// Total number of studies in the library.
    public var studyCount: Int { studies.count }

    /// Total number of series in the library.
    public var seriesCount: Int { series.count }

    /// Total number of instances in the library.
    public var instanceCount: Int { instances.count }

    /// Adds a study, merging it into one already known.
    ///
    /// A study is imported one file at a time, and the files disagree: a
    /// secondary capture may carry no Study Description, a scout no Study Date,
    /// a lone object no Modality. Replacing the record per file left the study
    /// describing whichever file happened to be read last — which is how a study
    /// with a full header ends up in the library showing nothing but a patient
    /// name. Every field is therefore filled from the first file that has it,
    /// and the modality set accumulates across the study.
    public mutating func addStudy(_ study: StudyModel) {
        if let existing = studies[study.studyInstanceUID] {
            studies[study.studyInstanceUID] = existing.merging(study)
        } else {
            studies[study.studyInstanceUID] = study
        }
        if studySeries[study.studyInstanceUID] == nil {
            studySeries[study.studyInstanceUID] = []
        }
    }

    /// Adds a series to the library, linking it to its parent study.
    public mutating func addSeries(_ seriesModel: SeriesModel) {
        series[seriesModel.seriesInstanceUID] = seriesModel
        studySeries[seriesModel.studyInstanceUID, default: []].insert(seriesModel.seriesInstanceUID)
        if seriesInstances[seriesModel.seriesInstanceUID] == nil {
            seriesInstances[seriesModel.seriesInstanceUID] = []
        }
    }

    /// Adds or updates an instance in the library, linking it to its parent series.
    ///
    /// If the instance already exists (same SOP Instance UID) and its series
    /// assignment has changed, the old series mapping is updated.
    public mutating func addInstance(_ instance: InstanceModel) {
        // If instance already exists, remove from old series mapping
        if let existing = instances[instance.sopInstanceUID],
           existing.seriesInstanceUID != instance.seriesInstanceUID {
            seriesInstances[existing.seriesInstanceUID]?.remove(instance.sopInstanceUID)
        }
        instances[instance.sopInstanceUID] = instance
        seriesInstances[instance.seriesInstanceUID, default: []].insert(instance.sopInstanceUID)
    }

    /// Removes a study and all its series and instances.
    public mutating func removeStudy(_ studyUID: String) {
        if let seriesUIDs = studySeries.removeValue(forKey: studyUID) {
            for seriesUID in seriesUIDs {
                if let instanceUIDs = seriesInstances.removeValue(forKey: seriesUID) {
                    for instanceUID in instanceUIDs {
                        instances.removeValue(forKey: instanceUID)
                    }
                }
                series.removeValue(forKey: seriesUID)
            }
        }
        studies.removeValue(forKey: studyUID)
    }

    /// Removes one instance, unlinking it from its series.
    ///
    /// The series itself is left in place even when this was its last instance:
    /// an empty series is a valid intermediate state — the caller may be about
    /// to add a replacement — and ``pruneEmptyStudies()`` is what clears the
    /// ones that stay empty.
    public mutating func removeInstance(_ sopInstanceUID: String) {
        guard let instance = instances.removeValue(forKey: sopInstanceUID) else { return }
        seriesInstances[instance.seriesInstanceUID]?.remove(sopInstanceUID)
    }

    /// Removes one series and every instance under it.
    public mutating func removeSeries(_ seriesInstanceUID: String) {
        if let instanceUIDs = seriesInstances.removeValue(forKey: seriesInstanceUID) {
            for uid in instanceUIDs {
                instances.removeValue(forKey: uid)
            }
        }
        if let removed = series.removeValue(forKey: seriesInstanceUID) {
            studySeries[removed.studyInstanceUID]?.remove(seriesInstanceUID)
        }
    }

    /// Drops studies and series that hold no instances.
    ///
    /// A study with nothing under it cannot be opened, printed or exported —
    /// it is a row that does nothing but claim a patient is in the library.
    /// Ones already saved to disk are cleared on load, so a library that
    /// collected them before they were prevented heals itself.
    /// - Returns: the number of studies removed.
    @discardableResult
    public mutating func pruneEmptyStudies() -> Int {
        let emptySeries = series.values
            .filter { (seriesInstances[$0.seriesInstanceUID]?.isEmpty ?? true) }
            .map(\.seriesInstanceUID)
        for seriesUID in emptySeries {
            series.removeValue(forKey: seriesUID)
            seriesInstances.removeValue(forKey: seriesUID)
            for (studyUID, uids) in studySeries where uids.contains(seriesUID) {
                studySeries[studyUID]?.remove(seriesUID)
            }
        }

        let emptyStudies = studies.keys.filter { studySeries[$0]?.isEmpty ?? true }
        for studyUID in emptyStudies {
            studies.removeValue(forKey: studyUID)
            studySeries.removeValue(forKey: studyUID)
        }
        return emptyStudies.count
    }

    /// Removes all data from the library.
    public mutating func clear() {
        studies.removeAll()
        series.removeAll()
        instances.removeAll()
        studySeries.removeAll()
        seriesInstances.removeAll()
    }

    /// Toggles the favorite status of a study.
    ///
    /// - Parameter studyUID: The Study Instance UID to toggle.
    /// - Returns: The new favorite state, or nil if the study was not found.
    @discardableResult
    public mutating func toggleFavorite(_ studyUID: String) -> Bool? {
        guard var study = studies[studyUID] else { return nil }
        study.isFavorite.toggle()
        studies[studyUID] = study
        return study.isFavorite
    }
}
