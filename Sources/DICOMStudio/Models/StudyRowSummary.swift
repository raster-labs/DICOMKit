// StudyRowSummary.swift
// DICOMStudio
//
// DICOM Studio — what a library row says about a study.
//
// A study record is assembled from study-level tags, and those tags are Type 2
// or Type 3: plenty of real exports carry no Study Description, and some carry
// no Modality or Modalities in Study either. The row then showed a patient name
// and nothing else, which reads as a broken import — while the series and
// instances filed under that study knew the modality and the description all
// along.
//
// So a row is built from the study *and* what is under it, not from the study
// record alone. One summary type, used by both the list and the grid, so the two
// cannot describe the same study differently.
//
// NEMA-verified: 2026a, checked 2026-10-05 — carries no DICOM-standard data (row text derived from the study, series
// and instance models).

import Foundation

public struct StudyRowSummary: Equatable, Sendable {

    /// Who the study belongs to, or the best identifier the study carries.
    public let patientName: String

    /// The study date, formatted, or "Unknown Date".
    public let studyDate: String

    /// What the exam is — nil only when neither the study nor any of its series
    /// says anything at all.
    public let description: String?

    /// "CT, SR". "Unknown" only when nothing under the study declares one.
    public let modalities: String

    /// "9 series · 582 images".
    public let counts: String

    public let seriesCount: Int
    public let instanceCount: Int

    /// Whether the library holds anything under this study.
    public var hasContent: Bool { instanceCount > 0 }

    public init(
        patientName: String,
        studyDate: String,
        description: String?,
        modalities: String,
        counts: String,
        seriesCount: Int,
        instanceCount: Int
    ) {
        self.patientName = patientName
        self.studyDate = studyDate
        self.description = description
        self.modalities = modalities
        self.counts = counts
        self.seriesCount = seriesCount
        self.instanceCount = instanceCount
    }

    /// Describes a study using everything the library knows about it.
    public static func make(study: StudyModel, library: LibraryModel) -> StudyRowSummary {
        let series = library.seriesForStudy(study.studyInstanceUID)

        // The study's own list first — it names modalities whose series may not
        // be in the library yet — then every series actually filed under it.
        var modalities = study.modalitiesInStudy
        for entry in series {
            let value = entry.modality.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { modalities.insert(value) }
        }

        return StudyRowSummary(
            patientName: study.displayPatientName,
            studyDate: study.displayStudyDate,
            description: description(of: study, series: series),
            modalities: modalities.isEmpty
                ? "Unknown" : modalities.sorted().joined(separator: ", "),
            counts: StudyBrowserHelpers.countBadge(
                series: series.count,
                instances: library.instanceCount(forStudy: study.studyInstanceUID)),
            seriesCount: series.count,
            instanceCount: library.instanceCount(forStudy: study.studyInstanceUID))
    }

    /// What to call the exam.
    ///
    /// Study Description if the study has one; otherwise the first series that
    /// describes itself, then the body part examined. A protocol name on the
    /// first series is what a reader recognises the study by when the study
    /// header is bare.
    private static func description(of study: StudyModel,
                                    series: [SeriesModel]) -> String? {
        if let value = nonEmpty(study.studyDescription) { return value }
        for entry in series {
            if let value = nonEmpty(entry.seriesDescription) { return value }
        }
        for entry in series {
            if let value = nonEmpty(entry.bodyPartExamined) { return value }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
