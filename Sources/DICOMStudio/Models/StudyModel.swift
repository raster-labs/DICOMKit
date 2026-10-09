// StudyModel.swift
// DICOMStudio
//
// DICOM Studio — Study-level metadata model
//
// NEMA-verified: 2026a, checked 2026-10-05 — fields mirror PS3.6 2026a Table 6-1 attributes (Study Instance UID,
// Study ID, Study Date, Study Description, Accession Number, Referring Physician's Name, Patient's Name, Patient ID,
// Patient's Sex, Institution Name, Modalities in Study); `patientDisplayName` joins PN components (PS3.5 2026a
// 6.2.1.1) for display only.

import Foundation

/// Represents a DICOM study containing one or more series.
///
/// A study is the primary organizational unit in DICOM, typically
/// corresponding to a single imaging session or exam.
public struct StudyModel: Identifiable, Hashable, Sendable {
    /// Unique identifier for this study model instance.
    public let id: UUID

    /// DICOM Study Instance UID (0020,000D).
    public let studyInstanceUID: String

    /// Study ID (0020,0010) assigned by the institution.
    public var studyID: String

    /// Study date (0008,0020).
    public var studyDate: Date?

    /// Study time (0008,0030).
    public var studyTime: Date?

    /// Study description (0008,1030).
    public var studyDescription: String?

    /// Accession number (0008,0050).
    public var accessionNumber: String?

    /// Referring physician's name (0008,0090).
    public var referringPhysicianName: String?

    /// Patient's name (0010,0010).
    public var patientName: String?

    /// Patient ID (0010,0020).
    public var patientID: String?

    /// Patient's birth date (0010,0030).
    public var patientBirthDate: Date?

    /// Patient's sex (0010,0040).
    public var patientSex: String?

    /// Institution name (0008,0080).
    public var institutionName: String?

    /// Number of series in this study.
    public var numberOfSeries: Int

    /// Number of instances in this study.
    public var numberOfInstances: Int

    /// Modalities present in the study (0008,0061).
    public var modalitiesInStudy: Set<String>

    /// File system path where study files are stored.
    public var storagePath: String?

    /// Whether this study is marked as a favorite.
    public var isFavorite: Bool

    /// Creates a new study model.
    public init(
        id: UUID = UUID(),
        studyInstanceUID: String,
        studyID: String = "",
        studyDate: Date? = nil,
        studyTime: Date? = nil,
        studyDescription: String? = nil,
        accessionNumber: String? = nil,
        referringPhysicianName: String? = nil,
        patientName: String? = nil,
        patientID: String? = nil,
        patientBirthDate: Date? = nil,
        patientSex: String? = nil,
        institutionName: String? = nil,
        numberOfSeries: Int = 0,
        numberOfInstances: Int = 0,
        modalitiesInStudy: Set<String> = [],
        storagePath: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.studyInstanceUID = studyInstanceUID
        self.studyID = studyID
        self.studyDate = studyDate
        self.studyTime = studyTime
        self.studyDescription = studyDescription
        self.accessionNumber = accessionNumber
        self.referringPhysicianName = referringPhysicianName
        self.patientName = patientName
        self.patientID = patientID
        self.patientBirthDate = patientBirthDate
        self.patientSex = patientSex
        self.institutionName = institutionName
        self.numberOfSeries = numberOfSeries
        self.numberOfInstances = numberOfInstances
        self.modalitiesInStudy = modalitiesInStudy
        self.storagePath = storagePath
        self.isFavorite = isFavorite
    }

    /// This study with anything it is missing filled in from another reading of
    /// the same study.
    ///
    /// Union rather than replacement: two files of one study describe the same
    /// exam, and the one that carries a Study Description does not become wrong
    /// because a later file omits it. Identity (`id`, `studyInstanceUID`) and
    /// user state (`isFavorite`) stay with the record already in the library.
    public func merging(_ other: StudyModel) -> StudyModel {
        var merged = self
        if merged.studyID.isEmpty { merged.studyID = other.studyID }
        merged.studyDate = merged.studyDate ?? other.studyDate
        merged.studyTime = merged.studyTime ?? other.studyTime
        merged.studyDescription = Self.preferred(merged.studyDescription, other.studyDescription)
        merged.accessionNumber = Self.preferred(merged.accessionNumber, other.accessionNumber)
        merged.referringPhysicianName = Self.preferred(
            merged.referringPhysicianName, other.referringPhysicianName)
        merged.patientName = Self.preferred(merged.patientName, other.patientName)
        merged.patientID = Self.preferred(merged.patientID, other.patientID)
        merged.patientBirthDate = merged.patientBirthDate ?? other.patientBirthDate
        merged.patientSex = Self.preferred(merged.patientSex, other.patientSex)
        merged.institutionName = Self.preferred(merged.institutionName, other.institutionName)
        merged.storagePath = Self.preferred(merged.storagePath, other.storagePath)
        // A study spans modalities — a CT with a dose SR, an MR with a scout —
        // so this accumulates rather than overwriting.
        merged.modalitiesInStudy.formUnion(other.modalitiesInStudy)
        merged.numberOfSeries = max(merged.numberOfSeries, other.numberOfSeries)
        merged.numberOfInstances = max(merged.numberOfInstances, other.numberOfInstances)
        merged.isFavorite = merged.isFavorite || other.isFavorite
        return merged
    }

    /// The first of two optional strings that actually says something.
    private static func preferred(_ lhs: String?, _ rhs: String?) -> String? {
        if let lhs, !lhs.trimmingCharacters(in: .whitespaces).isEmpty { return lhs }
        if let rhs, !rhs.trimmingCharacters(in: .whitespaces).isEmpty { return rhs }
        return lhs ?? rhs
    }

    /// Returns a display-friendly patient name (e.g., "Doe, John" from "Doe^John").
    ///
    /// A study with no Patient Name is still a study someone has to find again,
    /// so the row falls back to whatever does identify it — the patient ID, the
    /// description of the exam, the accession number — before admitting it knows
    /// nothing. "Unknown Patient" on a study that carries an ID is a label the
    /// library invented, not something the data says.
    public var displayPatientName: String {
        if let name = patientName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name.replacingOccurrences(of: "^", with: ", ")
        }
        for fallback in [patientID, studyDescription, accessionNumber, studyID] {
            if let value = fallback?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return "Unknown Patient"
    }

    /// Returns a formatted study date string or "Unknown Date".
    public var displayStudyDate: String {
        guard let date = studyDate else {
            return "Unknown Date"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Returns a short summary of modalities (e.g., "CT, MR").
    public var displayModalities: String {
        if modalitiesInStudy.isEmpty {
            return "Unknown"
        }
        return modalitiesInStudy.sorted().joined(separator: ", ")
    }
}
