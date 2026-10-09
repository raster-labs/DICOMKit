// InstanceModel.swift
// DICOMStudio
//
// DICOM Studio — Instance-level metadata model
//
// NEMA-verified: 2026a, checked 2026-10-05 — fields mirror PS3.6 2026a Table 6-1 attributes (SOP Instance UID, SOP
// Class UID, Series Instance UID, Instance Number, Transfer Syntax UID, Rows, Columns, Bits Allocated, Number of
// Frames, Photometric Interpretation); no standard values carried.

import Foundation

/// Represents a single DICOM instance (file).
///
/// An instance corresponds to one DICOM file, typically containing
/// a single image frame or document.
public struct InstanceModel: Identifiable, Hashable, Sendable {
    /// Unique identifier for this instance model.
    public let id: UUID

    /// DICOM SOP Instance UID (0008,0018).
    public let sopInstanceUID: String

    /// DICOM SOP Class UID (0008,0016).
    public let sopClassUID: String

    /// Parent Series Instance UID (0020,000E).
    public let seriesInstanceUID: String

    /// Instance number (0020,0013).
    public var instanceNumber: Int?

    /// File path on disk.
    public var filePath: String

    /// File size in bytes.
    public var fileSize: Int64

    /// Transfer syntax UID (0002,0010).
    public var transferSyntaxUID: String?

    /// Number of rows in the image (0028,0010).
    public var rows: Int?

    /// Number of columns in the image (0028,0011).
    public var columns: Int?

    /// Bits allocated per pixel (0028,0100).
    public var bitsAllocated: Int?

    /// Number of frames (0028,0008).
    public var numberOfFrames: Int?

    /// Photometric interpretation (0028,0004).
    public var photometricInterpretation: String?

    /// Creates a new instance model.
    public init(
        id: UUID = UUID(),
        sopInstanceUID: String,
        sopClassUID: String,
        seriesInstanceUID: String,
        instanceNumber: Int? = nil,
        filePath: String,
        fileSize: Int64 = 0,
        transferSyntaxUID: String? = nil,
        rows: Int? = nil,
        columns: Int? = nil,
        bitsAllocated: Int? = nil,
        numberOfFrames: Int? = nil,
        photometricInterpretation: String? = nil
    ) {
        self.id = id
        self.sopInstanceUID = sopInstanceUID
        self.sopClassUID = sopClassUID
        self.seriesInstanceUID = seriesInstanceUID
        self.instanceNumber = instanceNumber
        self.filePath = filePath
        self.fileSize = fileSize
        self.transferSyntaxUID = transferSyntaxUID
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.numberOfFrames = numberOfFrames
        self.photometricInterpretation = photometricInterpretation
    }

    /// Returns a human-readable file size string.
    public var displayFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    /// Returns a display title for this instance.
    public var displayTitle: String {
        if let num = instanceNumber {
            return "Instance \(num)"
        }
        return "Instance"
    }

    /// Returns image dimensions as a string if available.
    public var displayDimensions: String? {
        guard let r = rows, let c = columns else { return nil }
        return "\(c) × \(r)"
    }

    /// Whether this instance is a multi-frame instance.
    public var isMultiFrame: Bool {
        guard let frames = numberOfFrames else { return false }
        return frames > 1
    }
}
