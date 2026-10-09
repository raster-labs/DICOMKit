// NEMA-verified: 2026a, checked 2026-09-29 — workflow over the builder and parser; MIME types via EncapsulatedDocument
//
// EncapsulatedDocumentWorkflow.swift
// DICOMKit
//
// Shared orchestration helpers for the `dicom-pdf` workflow.
//
// The `dicom-pdf` CLI and the DICOMStudio in-process reimplementation must
// produce byte-identical output for CLI-parity. Both previously hand-mirrored
// the same small pieces of orchestration (document-type ↔ file-extension
// mapping, default modality, the human-readable size formatter, the
// `--show-metadata` text block, and the builder option chain). Those mirrors
// could silently drift. This file lifts that orchestration into the shared
// DICOMKit library so there is a single source of truth for both call sites.
//

import Foundation
import DICOMCore

// MARK: - Document type ↔ file extension / modality

public extension EncapsulatedDocumentType {

    /// The file extension used when extracting this document type to disk.
    ///
    /// Note: `.unknown` maps to `"bin"` (opaque binary payload).
    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .cda: return "xml"
        case .stl: return "stl"
        case .obj: return "obj"
        case .mtl: return "mtl"
        case .unknown: return "bin"
        }
    }

    /// Infers the document type from a file extension (case-insensitive).
    ///
    /// A leading dot is tolerated (`"pdf"` and `".pdf"` both resolve to `.pdf`).
    /// Unrecognized extensions resolve to `.unknown`.
    init(fileExtension ext: String) {
        switch ext.lowercased().drop(while: { $0 == "." }) {
        case "pdf": self = .pdf
        case "xml": self = .cda
        case "stl": self = .stl
        case "obj": self = .obj
        case "mtl": self = .mtl
        default:    self = .unknown
        }
    }

    /// The default DICOM Modality for this document type: `"M3D"` for 3D models
    /// (STL/OBJ/MTL), `"DOC"` for everything else.
    var defaultModality: String {
        switch self {
        case .stl, .obj, .mtl: return Modality.m3d.rawValue
        default:               return Modality.doc.rawValue
        }
    }
}

// MARK: - Shared formatting

public enum EncapsulatedDocumentFormatting {

    /// Human-readable byte size, shared verbatim by the `dicom-pdf` CLI and the
    /// Studio reimplementation (e.g. `"1.50 MB"`, `"512.00 KB"`, `"42 bytes"`).
    public static func fileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.2f KB", kb)
        } else {
            return "\(bytes) bytes"
        }
    }
}

// MARK: - Metadata report (`--show-metadata`)

public extension EncapsulatedDocument {

    /// Renders the human-readable metadata report emitted by `dicom-pdf
    /// --show-metadata`, shared verbatim by the CLI and the Studio
    /// reimplementation.
    ///
    /// The returned string begins and ends with a blank line, matching the
    /// original line-by-line `print()` sequence, so the CLI can emit it with
    /// `print(report, terminator: "")` and the app can append it directly.
    func metadataReport() -> String {
        var s = ""
        s += "\n"
        s += "Document Metadata:\n"
        s += "  Type: \(documentType)\n"
        s += "  MIME Type: \(mimeType)\n"
        s += "  Size: \(EncapsulatedDocumentFormatting.fileSize(Int64(documentData.count)))\n"
        s += "  SOP Class: \(sopClassUID)\n"
        s += "  SOP Instance: \(sopInstanceUID)\n"
        if let title = documentTitle { s += "  Title: \(title)\n" }
        s += "\n"
        s += "Patient Information:\n"
        if let pn = patientName { s += "  Name: \(pn)\n" }
        if let pid = patientID { s += "  ID: \(pid)\n" }
        s += "\n"
        s += "Study/Series:\n"
        s += "  Study UID: \(studyInstanceUID)\n"
        s += "  Series UID: \(seriesInstanceUID)\n"
        if let m = modality { s += "  Modality: \(m)\n" }
        if let sd = seriesDescription { s += "  Series Description: \(sd)\n" }
        if let sn = seriesNumber { s += "  Series Number: \(sn)\n" }
        if let inum = instanceNumber { s += "  Instance Number: \(inum)\n" }
        s += "\n"
        return s
    }
}

// MARK: - Builder option chain

public extension EncapsulatedDocumentBuilder {

    /// Applies the standard `dicom-pdf` encapsulation option set: required
    /// patient identity and modality, plus the optional title / series
    /// description / series number / instance number.
    ///
    /// Shared by the CLI's single-file and batch paths and the Studio
    /// reimplementation so the option-to-attribute mapping cannot drift.
    /// Pass `nil` for any optional to leave it unset.
    @discardableResult
    func applyStandardOptions(
        patientName: String,
        patientID: String,
        modality: String,
        title: String? = nil,
        seriesDescription: String? = nil,
        seriesNumber: Int? = nil,
        instanceNumber: Int? = nil
    ) -> Self {
        _ = setPatientName(patientName)
        _ = setPatientID(patientID)
        _ = setModality(modality)
        if let title, !title.isEmpty { _ = setDocumentTitle(title) }
        if let seriesDescription, !seriesDescription.isEmpty { _ = setSeriesDescription(seriesDescription) }
        if let seriesNumber { _ = setSeriesNumber(seriesNumber) }
        if let instanceNumber { _ = setInstanceNumber(instanceNumber) }
        return self
    }
}
