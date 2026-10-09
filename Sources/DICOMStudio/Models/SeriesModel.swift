// SeriesModel.swift
// DICOMStudio
//
// DICOM Studio — Series-level metadata model
//
// NEMA-verified: 2026a, checked 2026-10-05 — fields mirror PS3.6 2026a Table 6-1 attributes (Series Instance UID,
// Series Number, Modality, Series Description, Body Part Examined); default Modality "OT" is a PS3.3 2026a
// C.7.3.1.1.1 Defined Term.

import Foundation

/// Represents a DICOM series within a study.
///
/// A series groups related images, typically from a single acquisition
/// or reconstruction pass.
public struct SeriesModel: Identifiable, Hashable, Sendable {
    /// Unique identifier for this series model instance.
    public let id: UUID

    /// DICOM Series Instance UID (0020,000E).
    public let seriesInstanceUID: String

    /// Parent Study Instance UID (0020,000D).
    public let studyInstanceUID: String

    /// Series number (0020,0011).
    public var seriesNumber: Int?

    /// Modality (0008,0060).
    public var modality: String

    /// Series description (0008,103E).
    public var seriesDescription: String?

    /// Series date (0008,0021).
    public var seriesDate: Date?

    /// Body part examined (0018,0015).
    public var bodyPartExamined: String?

    /// Number of instances in this series.
    public var numberOfInstances: Int

    /// Transfer syntax UID used for instances in this series.
    public var transferSyntaxUID: String?

    /// Creates a new series model.
    public init(
        id: UUID = UUID(),
        seriesInstanceUID: String,
        studyInstanceUID: String,
        seriesNumber: Int? = nil,
        modality: String = "OT",
        seriesDescription: String? = nil,
        seriesDate: Date? = nil,
        bodyPartExamined: String? = nil,
        numberOfInstances: Int = 0,
        transferSyntaxUID: String? = nil
    ) {
        self.id = id
        self.seriesInstanceUID = seriesInstanceUID
        self.studyInstanceUID = studyInstanceUID
        self.seriesNumber = seriesNumber
        self.modality = modality
        self.seriesDescription = seriesDescription
        self.seriesDate = seriesDate
        self.bodyPartExamined = bodyPartExamined
        self.numberOfInstances = numberOfInstances
        self.transferSyntaxUID = transferSyntaxUID
    }

    /// Returns a display title combining series number and description.
    public var displayTitle: String {
        var parts: [String] = []
        if let num = seriesNumber {
            parts.append("Series \(num)")
        }
        if let desc = seriesDescription, !desc.isEmpty {
            parts.append(desc)
        }
        if parts.isEmpty {
            return "Unknown Series"
        }
        return parts.joined(separator: " — ")
    }
}
